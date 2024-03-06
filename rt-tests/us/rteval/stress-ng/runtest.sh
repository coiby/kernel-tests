#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export RTEVAL_DURATION=${RTEVAL_DURATION:-30s}

export TEST="rt-tests/us/rteval/stress-ng"
export result_r="PASS"

function check_status() # $1 = msg, $2 = status
{
    if [ $2 -eq 0 ]; then
        echo ":: $1 :: PASS ::" | tee -a $OUTPUTFILE
    else
        result_r="FAIL"
        echo ":: $1 :: FAIL ::" | tee -a $OUTPUTFILE
    fi
}

function runtest()
{
    echo "Package rteval stress-ng loads test:" | tee -a $OUTPUTFILE
    rm -f rteval.log

    # Verify stress-ng is installed
    rpm -q stress-ng || yum install -y stress-ng || {
        echo "Could not install stress-ng" | tee -a $OUTPUTFILE
        report_result $TEST "FAIL" 5
        exit 1
    }

    # Options for the stressng module:
    #   --stressng-option=OPTION
    #                       stressor specific option
    #   --stressng-arg=ARG  stressor specific arg
    #   --stressng-timeout=T
    #                       timeout after T seconds

    echo "-- CPU stressor: branch -----------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=branch --stressng-arg=0
    check_status "--stressng-option=branch --stressng-arg=0" $?

    echo "-- Cache stressor: cache ----------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=cache --stressng-arg=0
    check_status "--stressng-option=cache --stressng-arg=0" $?

    echo "-- Interrupt stressor: clock ------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=clock --stressng-arg=0
    check_status "--stressng-option=clock --stressng-arg=0" $?

    echo "-- Memory stressor: stack ---------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=stack --stressng-arg=0
    check_status "--stressng-option=stack --stressng-arg=0" $?

    echo "-- OS stressor: fifo --------------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=fifo --stressng-arg=0
    check_status "--stressng-option=fifo --stressng-arg=0" $?

    echo "-- OS stressor: lockf -------------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=lockf --stressng-arg=0
    check_status "--stressng-option=lockf --stressng-arg=0" $?

    echo "-- OS stressor: mlock -------------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=mlock --stressng-arg=0
    check_status "--stressng-option=mlock --stressng-arg=0" $?

    echo "-- OS stressor: pthread -----------------------" | tee -a $OUTPUTFILE
    rteval --duration=$RTEVAL_DURATION --stressng-option=pthread --stressng-arg=0
    check_status "--stressng-option=pthread --stressng-arg=0" $?

    if [ $result_r = "PASS" ]; then
        echo "Overall result: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall result: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

if rhel_in_range 0 8.2; then
    echo "Not supported in RHEL-RT < 8.3 -- skipping test case" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST "SKIP" 0
    exit 0
fi

runtest
exit 0
