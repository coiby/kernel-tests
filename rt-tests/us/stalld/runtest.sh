#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

###############################################################################
# I confimed that without stalld running and having the busyloop timeout set
# to $MAX_RUNTIME will result in the echo taking $MAX_RUNTIME seconds to complete.
#
# With stalld running the echo should complete in less than $MAX_RUNTIME. This tells
# us that the task is indeed being boosted. stalld will also print the PID of the
# process being boosted, giving additional confirmation.
###############################################################################

# Enable TMT testing for RHIVOS
. ../../../automotive/include/rhivos.sh || exit 1
: "${OUTPUTFILE:=runtest.log}"

# Source rt common functions
. ../../include/runtest.sh || exit 1

# Vars
export TEST="rt-tests/us/stalld"

rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')
rhel_minor=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $2}')
nrcpus=$(grep -c ^processor /proc/cpuinfo)
STALLD_PID=""
BUSYLOOP_PID=""
# Value is in seconds
MAX_RUNTIME=120

# Default ACTION=TEST: Is to run the stalld performance test.
# Non-Default ACTION=START: Is used to start and run stalld daemon  until
#   ACTION=STOP is recieved. This will allow us to introduce stalld daemon
#   running during select test cases.
# Non-Default ACTION=STOP: Is used to stop stalld
export ACTION=${ACTION:-"TEST"}

function install_and_start_stalld() {
    if ! kernel_automotive; then
        # Only run on 8.4 and up
        if ! (( ("$rhel_major" == 8 && "$rhel_minor" >= 4) || ("$rhel_major" > 8) )); then
            echo "stalld is only supported for RHEL >= 8.4 and up" || tee -a "$OUTPUTFILE"
            rstrnt-report-result $TEST "SKIP" 5
            exit 0
        fi
    fi

    if [ "$nrcpus" -eq 1 ]; then
        echo "stalld needs muliple cpus to run" || tee -a "$OUTFILE"
        rstrnt-report-result $TEST "SKIP" 1
        exit 0
    fi

    # Verify stalld is installed
    rpm -q stalld || yum install -y stalld || {
        echo "Could not install stalld" | tee -a "$OUTPUTFILE"
        rstrnt-report-result $TEST "FAIL" 5
        exit 1
    }

    # Enable stalld if needed
    systemctl status stalld.service >>"$OUTPUTFILE" 2>&1 || {
        echo "Starting stalld" | tee -a "$OUTPUTFILE"

        # Use a higher runtime ns for boosting, equal to 0.1s
        # With the default boost timing it will take multiple boosts
        # to finish the test and will take much longer
        stalld -v -A -t 30 -r 1000000 | tee -a "$OUTPUTFILE" &
        export STALLD_PID=$!
    }
}

function run_test() {
    echo "Compile rt_busyloop" | tee -a "$OUTPUTFILE"
    gcc -o rt_busyloop rt_busyloop.c

    # Run in a loop to get several readings
    declare -i ITERS=1
    while [[ $ITERS -lt 11 ]]; do
        START=$(date +%s)

        # Run a busy loop to stall cpu 1
        timeout "${MAX_RUNTIME}s" chrt -f 1 taskset -c 1 ./rt_busyloop &
        export BUSYLOOP_PID=$!

        # Print process info so we can see PIDs and tell if the right process
        # is getting boosted
        sh -c 'sleep 5; ps aux | tail' &

        # Sleep for a little bit, in case the timeout command is taking
        # some time to get scheduled
        sleep 1

        # This process blocks, and has to get boosted to finish
        chrt -f 1 taskset -c 1 sh -c "echo \"Finished\""

        END=$(date +%s)
        RUNTIME=$((END - START))

        if [[ $RUNTIME -lt $MAX_RUNTIME ]]; then
            echo "Iteration $ITERS runtime is $RUNTIME : PASS" | tee -a "$OUTPUTFILE"
            rstrnt-report-result "$TEST: iter $ITERS ${RUNTIME}s" "PASS" 0
        else
            echo "Iteration $ITERS runtime is $RUNTIME : FAIL" | tee -a "$OUTPUTFILE"
            rstrnt-report-result "$TEST: iter $ITERS ${RUNTIME}s" "FAIL" 1
        fi
        ITERS=$((ITERS + 1))
        kill "$BUSYLOOP_PID"
    done
}

function stop_stalld() {
    echo "Stoping stalld." | tee -a "$OUTPUTFILE"
    kill "$STALLD_PID" &
    sleep 10
    if ps -p $STALLD_PID >/dev/null; then
        echo "stalld did not respond to SIGTERM - using SIGKILL"
        kill -9 $STALLD_PID
    fi
}

# ----------------------------------------------------------------------------

if [ "$ACTION" == "TEST" ]; then
    echo "Running stalld performance test." | tee -a "$OUTPUTFILE"
    if ! kernel_automotive; then
        rt_env_setup # Should this be ran before START and STOP?
    fi
    install_and_start_stalld
    run_test
    stop_stalld
elif [ "$ACTION" == "START" ]; then
    echo "Check stalld installation and start stalld." | tee -a "$OUTPUTFILE"
    install_and_start_stalld
elif [ "$ACTION" == "STOP" ]; then
    echo "Stop stalld by running stop." | tee -a "$OUTPUTFILE"
    stop_stalld
fi
