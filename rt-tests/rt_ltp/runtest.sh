#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

TEST_VERSION=${TEST_VERSION:-20250130}
RTLTP_PROFILE=${RTLTP_PROFILE:-default}

# Source rt common functions
# shellcheck disable=SC1091
. ../include/runtest.sh || exit 1
# shellcheck disable=SC1091
. ../../distribution/ltp/include-ng/include.sh || exit 1
# shellcheck disable=SC1091
. ../../cki_lib/libcki.sh || exit 1

set -x

# Test name and paths
TEST="rt-tests/rt_ltp"
TESTPATH=$(pwd)
WORKSPACE="$HOME/rt_ltp"

TEST_TYPE=${TEST_TYPE:-"func"}
# TEST_TYPE = "func perf" to enable ./perf/latency

# $TESTVERSION is set in ltp-make.sh
ltp_version=${ltp_version:-$TESTVERSION}
result_r="PASS"

function check_status() {
    # $1: the ./run.sh command line
    # $2: return code from ./run.sh

    # Parse parameters
    local casename=""
    if [[ "$1" =~ "func/" ]]; then
        casename=$(echo "$1" | awk -F 'func/' '{print $2}')
    elif [[ "$1" =~ "perf/" ]]; then
        casename=$(echo "$1" | awk -F 'perf/' '{print $2}')
    fi

    if [[ -n "$casename" ]]; then
        echo "Got the casename '$casename' from command line '$1'."
    else
        echo "Failed to get casename from command line '$1'."
        rstrnt-report-result "${casename}" "WARN" 2
        return 2
    fi

    if [[ -z $2 ]]; then
        echo "Failed to receive the return code from './run.sh'."
        rstrnt-report-result "${casename}" "WARN" 2
        return 2
    fi

    # Analyse the return code
    if [[ $2 -ne 0 ]]; then
        result_r="FAIL"
        echo ":: $1 :: FAIL ::" | tee -a "$OUTPUTFILE"
        rstrnt-report-result "${casename}" "FAIL" 1
        return 1
    fi

    # Analyse the log files
    echo "Analysing test '$casename'..."
    local casestat="PASS"

    if [[ ! -d ./logs ]]; then
        echo "Directory $PWD/logs does not exist."
        rstrnt-report-result "${casename}" "WARN" 2
        return 2
    fi

    # Collect all the related log files
    local keywords=$casename
    [[ $casename = pi-tests ]] && keywords="testpi sbrk_mutex"
    [[ $casename = measurement ]] && keywords="rdtsc-latency preempt_timing"
    [[ $casename = thread_clock ]] && keywords=tc-2
    [[ $casename = latency ]] && keywords=pthread_cond_many

    local log_files=""
    for k in $keywords; do
        log_files+=$(find ./logs/ -name "*${k}*" -exec readlink -f {} \;)" "
    done

    local count=$(echo "$log_files" | wc -w)
    if [[ $count -eq 0 ]]; then
        # Skipping a test by commenting it out in the profile prevents it from
        # being executed and generating any logs.
        # Therefore, it should be treated as a SKIP, not a WARN.
        echo "No log files containing '$keywords' were found in $PWD/logs."
        echo "Test '$casename' is not being executed and does not produce any logs."
        echo ":: $1 :: SKIP ::" | tee -a "$OUTPUTFILE"
        rstrnt-report-result "${casename}" "SKIP" 0
        return 0
    else
        echo "Found $count log file(s) containing '$keywords':"
        for log_file in $log_files; do echo ">> $log_file"; done
    fi

    for log_file in $log_files; do
        # Examining the log file
        echo "Examining log file '$log_file'..."

        if grep -q "Result: FAIL" "$log_file"; then
            echo "Found 'Result: FAIL' exists in the log file."
            casestat="FAIL"
        fi

        # Upload the log file
        rstrnt-report-log -l "$log_file"
    done

    if [[ "$casestat" = "PASS" ]]; then
        echo ":: $1 :: PASS ::" | tee -a "$OUTPUTFILE"
        rstrnt-report-result "${casename}" "PASS" 0
        return 0
    else
        echo ":: $1 :: FAIL ::" | tee -a "$OUTPUTFILE"
        rstrnt-report-result "${casename}" "FAIL" 1
        result_r="FAIL"
        return 1
    fi
}

function setup() {
    if cki_is_kernel_automotive; then
        # Ensure the workspace directory exists and is accessible
        if [[ -z "$WORKSPACE" ]]; then
            rlLogError "WORKSPACE variable is not set."
        rstrnt-report-result "$TEST" WARN 1
            exit 1
        fi

        mkdir -p "$WORKSPACE"
        cd "$WORKSPACE" || {
            rlLogError "Unable to access workspace directory '$WORKSPACE'."
            rstrnt-report-result "$TEST" WARN 1
        exit 1
    }

    if [[ -f ./setup.txt ]]; then
            # LTP has already been set up, skip further initialization
            rlLog "Setup already completed previously. Skipping initialization."
            return
        else
            # Clean workspace to prepare for a fresh setup
            rlLog "Cleaning workspace directory before LTP setup."
            rm -rf ./*
        fi
    fi

    # Install required dependencies
    if ! $PKGMGR wget gcc make automake; then
        echo "Failed to install required packages: wget, gcc, make, automake." | tee -a "$OUTPUTFILE"
        rlLogError "Test aborted due to package installation failure."
        rstrnt-report-result "$TEST" WARN 1
        exit 1
    fi

    # Download and prepare the LTP suite
    download_ltp
    patch-rtltp

    if cki_is_kernel_automotive; then
        # Copy predefined test profiles to the appropriate LTP directory
        local profile_dir="$WORKSPACE/ltp-full-$ltp_version/testcases/realtime/profiles/"
        rlLog "Copying test profiles to: $profile_dir"
        cp -v "$TESTPATH"/profiles/* "$profile_dir"

        # Ensure the specified profile exists
        if [[ ! -f "$profile_dir/$RTLTP_PROFILE" ]]; then
            rlLogError "Profile '$RTLTP_PROFILE' not found in '$profile_dir'."
            rstrnt-report-result "$TEST" WARN 1
                        exit 1
        fi

        # Create a flag to indicate setup completion
        date >./setup.txt
        rlLog "LTP setup completed successfully."
    fi
}

function runtest() {
    pushd "ltp-full-$ltp_version" || exit 1
    ./configure

    pushd "testcases/realtime" || exit 1
    ./configure

    # default test-arguments: func, stress, perf, list
    func_list=$(./run.sh -t list | grep "${TEST_TYPE// /\\|}" | sed 's/^\s*//' | sort)

    if cki_is_kernel_automotive; then
        # If running on a debug kernel, check for a debug-specific profile variant
        local profile=$RTLTP_PROFILE
        if cki_is_kernel_debug; then
            local debug_profile="${RTLTP_PROFILE}-kdebug"
            if [[ -f "$WORKSPACE/ltp-full-$ltp_version/testcases/realtime/profiles/$debug_profile" ]]; then
                rlLog "Detected debug kernel. Switching to debug-specific profile: '$debug_profile'"
                profile="$debug_profile"
            else
                rlLog "Debug kernel detected, but no debug-specific profile '$debug_profile' found. Continuing with profile: '$RTLTP_PROFILE'."
            fi
        fi
    fi
    while IFS= read -r case; do
        echo "=== Running $case ==="
        ./run.sh -p "$profile" -t "$case"
        local return_code=$?
        echo "=== Checking $case ==="
        check_status "./run.sh -p $profile -t $case" $return_code
    done <<<"$func_list"

    # shellcheck disable=SC2164
    popd || exit # "testcases/realtime"
    popd || exit # "ltp-full-$ltp_version"

    if [ $result_r = "PASS" ]; then
        echo "overall result: PASS"
    else
        echo "overall result: FAIL"
    fi
}

rt_env_setup
setup
runtest
exit 0
