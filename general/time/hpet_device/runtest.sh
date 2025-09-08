#!/bin/bash

TEST="general/time/hpet_device"

hpet_cmd="./hpet_example"
hpet_device="/dev/hpet"
result_r="PASS"
: ${OUTPUTFILE:=runtest.log}

function check_status()
{
    if [ $? -eq 0 ]; then
        echo ":: $* :: PASS ::" | tee -a $OUTPUTFILE
    else
        result_r="FAIL"
        echo ":: $* :: FAIL ::" | tee -a $OUTPUTFILE
    fi
}

function check_hpet_device()
{
    if [ -e $hpet_device ]; then
        echo "hpet device exist" | tee -a $OUTPUTFILE
        return 0
    else
        echo "$hpet_device does not exist" | tee -a $OUTPUTFILE
        rstrnt-report-result "check_hpet_device" "FAIL" "1"
        exit 1
    fi
}

function runtest()
{
    echo "Check hpet device" | tee -a $OUTPUTFILE
    check_hpet_device

    echo "run $hpet_cmd info" | tee -a $OUTPUTFILE
    $hpet_cmd info $hpet_device
    check_status "$hpet_cmd info $hpet_device"

    echo "run $hpet_cmd open-close" | tee -a $OUTPUTFILE
    $hpet_cmd open-close $hpet_device
    check_status "$hpet_cmd open-close $hpet_device"

    echo "run $hpet_cmd poll" | tee -a $OUTPUTFILE
    $hpet_cmd poll $hpet_device 5 10
    check_status "$hpet_cmd poll $hpet_device 5 10"

    echo "run $hpet_cmd fasync" | tee -a $OUTPUTFILE
    $hpet_cmd fasync $hpet_device 5 10
    check_status "$hpet_cmd fasync $hpet_device 5 10"

    if [ $result_r = "PASS" ]; then
        echo "Overall result: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall result: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

# start
echo "hpet device check only run x86_64" | tee -a $OUTPUTFILE
gcc hpet_example.c -o hpet_example
if [ $(uname -m) = "x86_64" ]; then
    runtest
else
    rstrnt-report-result $TEST "SKIP" 0
fi
exit 0
