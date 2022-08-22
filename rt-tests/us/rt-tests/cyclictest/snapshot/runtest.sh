#!/bin/bash

export TEST="rt-tests/us/rt-tests/cyclictest/snapshot"
export result_r="PASS"
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

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
    declare pkg_name="rt-tests" && [ $rhel_major -ge 9 ] && pkg_name="realtime-tests"

    echo "Package rt-tests for cyclictest snapshot test." | tee -a $OUTPUTFILE
    rpm -q --quiet $pkg_name || yum install -y $pkg_name
    check_status "install rt-tests"

    echo "Cleaning /dev/shm/" | tee -a $OUTPUTFILE
    rm -f /dev/shm/cyclic*

    echo "Running cyclictest on backgroud." | tee -a $OUTPUTFILE
    cyclictest -q &
    declare cyc_pid=$!
    echo "cyclictest pid: $cyc_pid" | tee -a $OUTPUTFILE
    sleep 10

    cyc_dev=$(find /dev/shm/ -name 'cyclic*' -print | head -n 1)
    [ ! -f $cyc_dev ] && {
        result_r="FAIL"
        echo "cyclictest_shm file doesn't exist!" | tee -a $OUTPUTFILE
    }

    echo "Send USR2 to cyclictest process to check snapshot." | tee -a $OUTPUTFILE
    kill -s USR2 $cyc_pid
    grep "^T:" $cyc_dev || {
        result_r="FAIL"
        echo "Didn't get the snapshot data." | tee -a $OUTPUTFILE
    }
    sleep 10

    if which get_cyclictest_snapshot >/dev/null ; then
        # package is rt-tests >= v1.8, so test this utility
        get_cyclictest_snapshot
        if [ $? -ne 0 ]; then
            result_r="FAIL"
            echo "get_cyclictest_snapshot utility failed" | tee -a $OUTPUTFILE
        fi
    fi

    kill -9 $cyc_pid

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
