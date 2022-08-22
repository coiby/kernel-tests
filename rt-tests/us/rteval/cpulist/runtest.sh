#!/bin/bash

export MCPU=${MCPU:-1}
export LCPU=${LCPU:-2}

export TEST="rt-tests/us/rteval/cpulist"
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
    echo "Package rteval cpulist test:" | tee -a $OUTPUTFILE
    rm -f rteval.log

    echo "-- run rteval ----------------------------------" | tee -a $OUTPUTFILE
    rteval --measurement-cpulist=$MCPU --loads-cpulist=$LCPU --duration=10m > rteval.log &
    declare rtpid=$!

    echo "-- wait for threads to start -------------------" | tee -a $OUTPUTFILE
    sleep 90

    echo "-- view measurement threads --------------------" | tee -a $OUTPUTFILE
    declare -i status=1
    for _ in {1..10}; do
        ps -eLo psr,args,pid | grep "$MCPU cyclictest"
        if [ $? -eq 0 ]; then
            status=0
            break
        else
            sleep 5
        fi
    done
    check_status "measurement thread found and scheduled on CPU $MCPU" $status

    echo "-- view compile threads ------------------------" | tee -a $OUTPUTFILE
    status=1
    for _ in {1..10}; do
        ps -eLo psr,args | sort | uniq | grep "^  $LCPU make O=/" | grep "rteval-build"
        if [ $? -eq 0 ]; then
            status=0
            break
        else
            sleep 5
        fi
    done
    check_status "compile load thread found and scheduled on CPU $LCPU" $status

    echo "-- view hackbench threads ----------------------" | tee -a $OUTPUTFILE
    status=1
    for _ in {1..10}; do
        ps -eLo psr,args | sort | uniq | grep -e "^  $LCPU hackbench" -e "^  $LCPU \[hackbench\]"
        if [ $? -eq 0 ]; then
            status=0
            break
        else
            sleep 5
        fi
    done
    check_status "hackbench thread found and scheduled on CPU $LCPU" $status

    echo "-- wait for rteval PID -------------------------" | tee -a $OUTPUTFILE
    wait $rtpid

    echo "-- verify measurement CPUs ---------------------" | tee -a $OUTPUTFILE
    declare measurement_cpus=$(grep 'measurement threads on cores' rteval.log | awk '{print $NF}' | xargs)
    [[ "$measurement_cpus" == "$MCPU" ]]
    check_status "measurement threads output - expected:$MCPU got:$measurement_cpus" $?

    echo "-- verify loads CPUs ---------------------------" | tee -a $OUTPUTFILE
    declare loads_cpus=$(grep 'loads on cores' rteval.log | sed 's/with.*//' | awk '{print $NF}' | xargs)
    [[ "$loads_cpus" == "$LCPU" ]]
    check_status "load threads output - expected:$LCPU got:$loads_cpus" $?

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
