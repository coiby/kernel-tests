#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../cki_lib/libcki.sh || exit 1

export TEST=syscalls_latency

LTP_VERSION=${LTP_VERSION:-20250130}
mm_syscalls=${mm_syscalls:-'abort01'}
exclude_ltp_tests=${exclude_ltp_tests:-''}
timer=${timer:-180}

# Get and build LTP/syscalls testsuite
function setup_ltp()
{
    git clone --recurse-submodules https://gitlab.com/redhat/centos-stream/tests/ltp.git
    pushd ltp
    rlRun "git checkout $LTP_VERSION"
    rlRun "make autotools"
    rlRun "./configure"
    pushd testcases/kernel/syscalls/
    export syscalls_test_path=$(pwd)
    IFS=',' read -ra folders <<< "$(echo "${mm_syscalls//\"/}" | tr -d '\n')"
    for folder in "${folders[@]}"; do
        # Trim leading and trailing whitespace
        folder=$(echo "$folder" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Construct absolute path
        full_path="$syscalls_test_path/$folder"
        if [[ -d "$full_path" ]]; then
            rlRun "make -C $full_path"
        else
            echo "Warning: $full_path is not a directory"
        fi
    done
    popd
    popd
}

# Function to check if a file is in the excluded list
function is_excluded() {
    local file="$1"
    local basename=$(basename "$file")
    IFS=',' read -ra excluded_execs <<< "$(echo "${exclude_ltp_tests//\"/}" | tr -d '\n')"
    for excluded in "${excluded_execs[@]}"; do
        if [[ "$basename" == "$excluded" ]]; then
            return 0  # True, it is excluded
        fi
    done
    return 1  # False, it is not excluded
}

# Get syscalls in scope list, execute LTP/syscalls tests for each one.
# Parameter is run time in seconds, default is 60 seconds.
function run_ltp_syscalls_concurrently() {
    IFS=',' read -ra folders <<< "$(echo "${mm_syscalls//\"/}" | tr -d '\n')"
    deadline=$(($SECONDS + ${1:-60}))

    # Ensure the container is running
    if ! podman inspect -f '{{.State.Running}}' qm &>/dev/null; then
        echo "Error: The 'qm' container is not running."
        return 1
    fi

    while [[ $SECONDS -lt $deadline ]]; do
        jobs=()  # Track background jobs
        commands=()  # Collect syscall paths

        for folder in "${folders[@]}"; do
            # Trim leading and trailing whitespace
            folder=$(echo "$folder" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            # Construct absolute path
            full_path="$syscalls_test_path/$folder"

            # Iterate over executables and collect them
            if [[ -d "$full_path" ]]; then
                while IFS= read -r -d '' file; do
                    if [[ -x "$file" ]] && ! is_excluded "$file"; then
                        commands+=("$file")  # Collect executable paths
                    fi
                done < <(find "$full_path" -type f -executable -print0 | sort -z)
            else
                echo "Warning: $full_path is not a directory"
            fi
        done

        if [[ ${#commands[@]} -gt 0 ]]; then
            echo "Executing ${#commands[@]} syscalls in batches of 10"

            for ((i = 0; i < ${#commands[@]}; i += 10)); do
                batch=("${commands[@]:i:10}")  # Get a batch of 10

                # Run podman exec in the background and track jobs
                podman exec -it qm bash -c "$(printf '%q\n' "${batch[@]}")" &
                jobs+=($!)  # Store process ID
            done

            # Wait for all background jobs to finish before the next cycle
            for job in "${jobs[@]}"; do
                wait "$job"
            done
        fi
    done
}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        if ! cki_is_kernel_automotive; then
            rlLog "Skipping $TEST: This test is intended to run only in the RHIVOS environment."
            rstrnt-report-result "$TEST" SKIP
            rlJournalEnd
            exit 0
        fi
        rlRun setup_ltp

        # Setup container mountpoints, if not done during prepare step (all:qm/scripts/beaker-prepare.sh)
        if [[ ! -f /etc/containers/systemd/qm.container.d/volume.conf ]]; then
            mkdir -p /etc/containers/systemd/qm.container.d
            cat > /etc/containers/systemd/qm.container.d/ltp_syscalls.conf << EOF
[Container]
Volume=${syscalls_test_path}:${syscalls_test_path}:z
EOF
            cat /etc/containers/systemd/qm.container.d/ltp_syscalls.conf
            rlRun "systemctl daemon-reload"
            rlRun "systemctl restart qm"
        fi
    rlPhaseEnd
    rlPhaseStartTest "Concurrent syscall execution in parallel with latency test"

        # Measure the latency with timerlat
        echo "Running rtla-timerlat-hist to measure system latency."

        # Temporarily stop the timerlat tracing service if it is active (VROOM-23444)
        if systemctl is-active --quiet timerlat_trace; then
            echo "'timerlat_trace' service is currently active. Temporarily stopping it to avoid conflicts."
            systemctl stop timerlat_trace && echo "'timerlat_trace' service has been stopped temporarily."
            restore_timerlat_service=1
        else
            echo "'timerlat_trace' service is not active. Proceeding with the test."
            restore_timerlat_service=0
        fi

        rtla timerlat hist -d "24h" -u | tee timerlat_hist.txt & # Run latency test in the background

        # Execute concurrent syscalls workload
        run_ltp_syscalls_concurrently $timer &
        syscall_pid=$!

        wait $syscall_pid
        killall -s SIGINT rtla

        # Ensure the background process is cleaned up
        wait

        # Extract the maximum latency value from the timerlat_hist.txt file and log the latency results
        max_latency=$(grep "max:" timerlat_hist.txt | awk -F":" '{print $2}' | tr ' ' '\n' | grep -E "[0-9]+" | awk '$0>x {x=$0}; END{print x}')
        rstrnt-report-log -l ./timerlat_hist.txt

        if [[ -z $max_latency ]]; then
            echo "FAIL: Unable to get maximum latency."
            echo "Refer to timerlat_hist.txt for detailed results."
            rstrnt-report-result "$TEST" "FAIL"
        elif [[ $max_latency -gt $RHIVOS_THRES ]]; then
            echo "FAIL: Maximum latency is $max_latency which exceeds threshold $RHIVOS_THRES."
            echo "Refer to timerlat_hist.txt for detailed results."
            rstrnt-report-result "$TEST" "FAIL"
        else
            echo "PASS: System latency within acceptable range, maximum latency $max_latency."
            rstrnt-report-result "$TEST" "PASS"
        fi

        # Restore the timerlat tracing service if it was stopped earlier
        if [[ $restore_timerlat_service -eq 1 ]]; then
            echo "Restoring 'timerlat_trace' service..."
            systemctl start timerlat_trace && echo "'timerlat_trace' service is active again."
        fi
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
