#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


# Source rt common functions
. ../include/runtest.sh  || exit 1
. ../../distribution/ltp/include/ltp-make.sh || exit 1

TEST="rt-tests/rt_ltp"

TEST_TYPE=${TEST_TYPE:-"func"}
# TEST_TYPE = "func perf" to enable ./perf/latency

# $TESTVERSION is set in ltp-make.sh
ltp_version=${ltp_version:-$TESTVERSION}
result_r="PASS"

function check_status()
{
    if [ $? -eq 0 ]; then
        echo ":: $* :: PASS ::" | tee -a "$OUTPUTFILE"
    else
        result_r="FAIL"
        echo ":: $* :: FAIL ::" | tee -a "$OUTPUTFILE"
    fi
}

function runtest()
{
    $PKGMGR wget gcc make automake || {
        echo "dependent package install failed" | tee -a "$OUTPUTFILE"
        rstrnt-report-result $TEST WARN 1
        rlLog "Aborting test because dependent package install failed"
        rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
        exit 1
    }

    # Downoad and setup ltp
    download_ltp

    pushd "ltp-full-$ltp_version" || exit 1
    ./configure

    pushd "testcases/realtime" || exit 1
    ./configure

    # default test-arguments: func, stress, perf, list
    func_list=$(./run.sh -t list | grep "${TEST_TYPE// /\\|}")
    while IFS= read -r case; do
        echo "running $case"
        ./run.sh -t "$case"
        check_status "./run.sh -t $case"
    done <<< "$func_list"
    # shellcheck disable=SC2164
    popd

    if [ $result_r = "PASS" ]; then
        echo "overall result: PASS" | tee -a "$OUTPUTFILE"
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "overall result: FAIL" | tee -a "$OUTPUTFILE"
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

rt_env_setup
runtest
exit 0
