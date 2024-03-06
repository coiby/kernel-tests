#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rt-tests/sanity"
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
    local rt_tests_pkg="rt-tests" && [ $rhel_x -ge 9 ] && rt_tests_pkg="realtime-tests"
    echo "Package rt-tests sanity test:" | tee -a $OUTPUTFILE

    rpm -q --quiet $rt_tests_pkg || yum install -y $rt_tests_pkg
    check_status "install $rt_tests_pkg"


    # Note: test changing the runtime/deadline/period parameters of cyclicdeadline's
    #       current scheduling policy for SCHED_DEADLINE
    echo "-- cyclicdeadline -----------------------------" | tee -a $OUTPUTFILE
    cyclicdeadline 1>/dev/null 2>&1 &
    sleep 1
    deadline_pid=$(chrt -a -p "$(pgrep cyclicdeadline)" | grep SCHED_DEADLINE | grep -o -P "(?<=pid ).*(?='s)")
    chrt -T 580000 -P 990000 -D 990000 -d -p 0 $deadline_pid
    chrt -a -p "$(pgrep cyclicdeadline)"
    chrt -a -p "$(pgrep cyclicdeadline)" | grep '580000/990000/990000'
    check_status "cyclicdeadline"
    pkill -9 cyclicdeadline


    # Multiple tests: (1) basic 30s run with smp, (2) test tracemark option
    # functions [1753005], (3) test threads > cpu count [1749956]
    echo "-- cyclictest ---------------------------------" | tee -a $OUTPUTFILE
    cyclictest --smp -umq -p95 --duration=30s
    check_status "cyclictest --smp -umq -p95 --duration=30s"
    cyclictest -i 100 -umq -p95 -t 4 -b 1 --tracemark --duration=30s
    check_status "cyclictest -i 100 -umq -p95 -t 4 -b 1 --tracemark --duration=30s"
    cyclictest -t $(( nrcpus * 2 )) -q --duration=10s
    check_status "cyclictest -t $(( nrcpus * 2 )) -q --duration=10s"


    echo "-- deadline_test ------------------------------" | tee -a $OUTPUTFILE
    deadline_test -i 1000
    check_status "deadline_test -i 1000"


    echo "-- hackbench ----------------------------------" | tee -a $OUTPUTFILE
    hackbench --process --groups 36 --loops 1000 --datasize 1000
    check_status "hackbench --process --groups 36 --loops 1000 --datasize 1000"


    # Note: threshold arbitrarily picked, because non-tuned systems
    #       may not meet the lower 10us default threshold.  We are more
    #       interested in sanity/functionality than performance in this test.
    echo "-- hwlatdetect --------------------------------" | tee -a $OUTPUTFILE
    hwlatdetect --duration=30s --threshold=2000
    check_status "hwlatdetect --duration=30s --threshold=500"


    if rpm -ql $rt_tests_pkg | grep -q 'oslat' ; then
        echo "-- oslat --------------------------------------"
        declare duration_flag="--duration" && oslat --help | grep -q '\-\-runtime' && duration_flag="--runtime"
        oslat --cpu-list 1 --rtprio 1 $duration_flag 30s
        check_status "oslat --cpu-list 1 --rtprio 1 ${duration_flag} 30s"
    fi


    echo "-- pi_stress ----------------------------------" | tee -a $OUTPUTFILE
    pi_stress --quiet --duration=30
    check_status "pi_stress --quiet --duration=30"


    # Note: likely that no inversion will occur, but we will still verify the
    #       process at least runs and exits successfully.  A timeout is added
    #       so that if this program hangs, it will not abort the test case.
    echo "-- pip_stress ---------------------------------" | tee -a $OUTPUTFILE
    timeout 5m pip_stress
    check_status "pip_stress"


    echo "-- pmqtest ------------------------------------" | tee -a $OUTPUTFILE
    pmqtest --loops=1000 --interval=1000 --prio=99
    check_status "pmqtest --loops=1000 --interval=1000 --prio=99"


    echo "-- ptsematest ---------------------------------" | tee -a $OUTPUTFILE
    ptsematest --affinity --loops=1000 --interval=1000 --prio=99 --threads
    check_status "ptsematest --affinity --loops=1000 --interval=1000 --prio=99 --threads"


    if rpm -ql $rt_tests_pkg | grep -q 'queuelat' ; then
        echo "-- queuelat -----------------------------------" | tee -a $OUTPUTFILE
        queuelat -m 20us -c 100 -p 100 -f 1000 -t 60s
        check_status "queuelat -m 20us -c 100 -p 100 -f 1000 -t 60s"
    fi


    echo "-- rt-migrate-test ----------------------------" | tee -a $OUTPUTFILE
    rt-migrate-test $nrcpus
    check_status "rt-migrate-test $nrcpus"


    # Note: many of the /proc/sys/kernel/* interfaces do not exist in RHEL-8+
    echo "-- signaltest ---------------------------------" | tee -a $OUTPUTFILE
    signaltest -b 20us -l 100 -q -t 10 -m -v
    check_status "signaltest -b 20us -l 100 -q -t 10 -m -v"


    echo "-- sigwaittest --------------------------------" | tee -a $OUTPUTFILE
    sigwaittest -a -b 20us -f -i 100 -l 100 -t 10
    check_status "sigwaittest -a -b 20us -f -i 100 -l 100 -t 10"


    if rpm -ql $rt_tests_pkg | grep -q 'ssdd' ; then
        echo "-- ssdd ---------------------------------------" | tee -a $OUTPUTFILE
        ssdd 10 10000
        check_status "ssdd 10 10000"
    fi


    echo "-- svsematest ---------------------------------" | tee -a $OUTPUTFILE
    svsematest -a -b 20us -f -i 100 -l 100 -S
    check_status "svsematest -a -b 20us -f -i 100 -l 100 -S"


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
