#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/python-schedutils/sanity"
export result_r="PASS"

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
    echo "Package python-schedutils sanity test:" | tee -a $OUTPUTFILE
    if [ $rhel_x -ge 9 ]; then
        echo "python3-schedutils removed from rhel-9" || tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" 5
        exit 0
    fi

    if [ $rhel_x -lt 8 ]; then
        rpm -q --quiet python-schedutils || yum install -y python-schedutils
        check_status "install python-schedutils"
    else
        rpm -q --quiet python3-schedutils || yum install -y python3-schedutils
        check_status "install python3-schedutils"
    fi

    echo "INFO: Running 'sleep 1d' in background" | tee -a $OUTPUTFILE
    sleep 1d &
    sleep 1
    declare sleep_pid=$(pgrep -f 'sleep 1d')

    echo "-- pchrt: view sched policy -------------------" | tee -a $OUTPUTFILE
    timeout 1m pchrt -p $sleep_pid
    check_status "pchrt -p $sleep_pid"

    echo "-- pchrt: change policy -----------------------" | tee -a $OUTPUTFILE
    timeout 1m pchrt --fifo -p 1 $sleep_pid
    check_status "pchrt --fifo -p 1 $sleep_pid"
    timeout 1m pchrt -p $sleep_pid | grep SCHED_FIFO
    check_status "pchrt -p $sleep_pid | grep SCHED_FIFO"

    # kill current 'sleep 1d' so we can spawn a new one for the following test
    kill -9 $sleep_pid ; wait $sleep_pid 2>/dev/null

    if [ $nrcpus -gt 2 ]; then
        echo "-- ptaskset: start 'sleep 1d' on CPU 1 & 2 ----" | tee -a $OUTPUTFILE
        ptaskset -c 1,2 sleep 1d &
        check_status "ptaskset -c 1,2 sleep 1d &"
        sleep 1
        sleep_pid=$(pgrep -f 'sleep 1d')

        echo "-- ptaskset: verify affinity mask -------------" | tee -a $OUTPUTFILE
        ptaskset -c -p $sleep_pid
        check_status "ptaskset -c -p $sleep_pid"
        ptaskset -c -p $sleep_pid | grep '1,2'
        check_status "ptaskset -c -p $sleep_pid | grep '1,2'"

        # kill final 'sleep 1d' prog
        kill -9 $sleep_pid ; wait $sleep_pid 2>/dev/null
    else
        echo "Only 2 CPU - skipping 'ptaskset -c 1,2 sleep 1d &' test" | tee -a $OUTPUTFILE
    fi

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
