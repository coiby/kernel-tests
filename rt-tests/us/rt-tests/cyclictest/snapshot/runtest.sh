#!/bin/bash

# Source rt common functions
. ../../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rt-tests/cyclictest/snapshot"
export result_r="PASS"
export rhel_x

function check_status()
{
    if [ $? -eq 0 ]; then
        echo ":: $* :: PASS ::" | tee -a $OUTPUTFILE
    else
        result_r="FAIL"
        echo ":: $* :: FAIL ::" | tee -a $OUTPUTFILE
    fi
}

function runtest()
{
    declare rt_tests_pkg="rt-tests" && [ $rhel_x -ge 9 ] && rt_tests_pkg="realtime-tests"

    rpm -q --quiet $rt_tests_pkg || yum install -y $rt_tests_pkg
    check_status "install ${rt_tests_pkg}"

    echo "Cleaning /dev/shm/..." | tee -a $OUTPUTFILE
    rm -f /dev/shm/cyclictest*

    cyclictest -q &
    declare cyc_pid=$!
    echo "Running cyclictest in the backgroud: ${cyc_pid}" | tee -a $OUTPUTFILE
    sleep 10


    # Every running cyclictest process possesses a file under /dev/shm
    test -f /dev/shm/cyclictest${cyc_pid}
    check_status "test -f /dev/shm/ cyclictest${cyc_pid}"

    # SIGUSR2 support added since rt-tests-v1.6
    kill -SIGUSR2 $cyc_pid
    grep "^T:" /dev/shm/cyclictest${cyc_pid}
    check_status "grep \"^T:\" /dev/shm/cyclictest${cyc_pid}"
    sleep 10


    # get_cyclictest_snapshot added since rt-tests-v1.7
    if which get_cyclictest_snapshot >/dev/null ; then
        get_cyclictest_snapshot -l | grep -q $cyc_pid
        check_status "get_cyclictest_snapshot -l | grep -q ${cyc_pid}"
        get_cyclictest_snapshot -s $cyc_pid
        check_status "get_cyclictest_snapshot -s ${cyc_pid}"
        get_cyclictest_snapshot -p $cyc_pid | grep "^T:"
        check_status "get_cyclictest_snapshot -p ${cyc_pid} | grep \"^T:\""
    fi


    kill -SIGTERM $cyc_pid || {
        kill -SIGKILL $cyc_pid
        rm -f /dev/shm/cyclictest${cyc_pid}
    }


    if [ $result_r = "PASS" ]; then
        echo "Overall result: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall result: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

runtest
exit 0
