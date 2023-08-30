#!/bin/bash

TEST="general/time/gettimeofday_perf"
: ${OUTPUTFILE:=runtest.log}

function runtest ()
{
    ClockSourceFile=/sys/devices/system/clocksource/clocksource0/current_clocksource
    ClockSource=$(cat $ClockSourceFile)

    if [ $ClockSource = "tsc" ]; then
        echo "ClockSource is TSC"
        echo "Running the routine, Please wait for a moment......"
        temp=$(./file 60 32)
        number=$(echo $temp | sed 's/+$//g')
        count=$(echo $[$number])
        echo  "The count is : $count"

        if [ $count -lt 6000000000 ]; then
            echo "### WARN ###"
            echo "test WARN:" >>$OUTPUTFILE 2>&1
            rstrnt-report-result $TEST "WARN" 0
        else
            echo "### Pass ###"
            echo "test Passed:" >>$OUTPUTFILE 2>&1
            rstrnt-report-result $TEST "PASS" 0
        fi
    elif [ $ClockSource = "hpet" ]; then
        echo "ClockSource is HPET"
        echo "Running the routine,, Please wait for a moment......"
        temp=$(./file 60 32)
        number=$(echo $temp | sed 's/+$//g')
        count=$(echo $[$number])
        echo  "The count is : $count"

        if [ $count -lt 150000000 ]; then
            echo "### WARN ###"
            echo "test WARN:" >>$OUTPUTFILE 2>&1
            rstrnt-report-result $TEST "WARN" 0
        else
            echo "### Pass ###"
            echo "test Passed:" >>$OUTPUTFILE 2>&1
            rstrnt-report-result $TEST "PASS" 0
        fi
    else
        echo "Other clocksource ......(exit) WARN"
        rstrnt-report-result $TEST "WARN" 0
    fi
}

# ---------- Start Test -------------
[[ ! $(uname -m) =~ "86" ]] && {
    echo "The current architecture is $(uname -m), this cast just support x86 architecture!"
    rstrnt-report-result $TEST "SKIP"
    exit 0
}
# echo tsc > /sys/devices/system/clocksource/clocksource0/current_clocksource
gcc file.c -o file
if [ $? -ne 0 ]; then
    echo "file.c compilation fails!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

runtest
exit 0
