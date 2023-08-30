#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/c_state_nohzoff"
RESULT="PASS"

[ -z $RSTRNT_REBOOTCOUNT ] && {
    echo "RSTRNT_REBOOTCOUNT not set - setting to 0 for manual run" | tee -a $OUTPUTFILE
    export RSTRNT_REBOOTCOUNT=0
}

function runtest ()
{
    echo "Reboot done" | tee -a $OUTPUTFILE
    grep "tsc=reliable nohz=off" /proc/cmdline >& /dev/null
    if [ $? -eq 0 ]; then
        echo "Setting successfully" | tee -a $OUTPUTFILE
    else
        echo "Setting failed" | tee -a $OUTPUTFILE
        RESULT="FAIL"
    fi

    echo "Starting checking the current clock source" | tee -a $OUTPUTFILE
    CLOCK_SOURCE=`cat /sys/devices/system/clocksource/clocksource0/current_clocksource`

    if [ $CLOCK_SOURCE != "tsc" ];then
        echo "FAIL:ClockSource should be TSC" | tee -a $OUTPUTFILE
        RESULT="FAIL"
    fi

    echo "The current clock source = $CLOCK_SOURCE" | tee -a $OUTPUTFILE
    echo "Starting checking the C-state" | tee -a $OUTPUTFILE

    if [[ $(uname -r) =~ "el7" ]] ; then
        powertop --time=60 --html=powertop.html
        rstrnt-report-log -l powertop.html
    else
        timeout 60 powertop -t 60 2>&1 | tee powertop.output | tee -a $OUTPUTFILE
    fi

    grep "^C[1-6]" powertop.output  | awk '{print $1, $4 $5}' | tr -d '[()%]' > /tmp/C_STATE

    i=0
    COUNT=`cat /tmp/C_STATE | wc -l`
    while read line
    do
        ((i++))
        if [ $i -gt $COUNT ]; then
            break
        fi

        temp=`echo $line | cut -d ' ' -f 2`
        temp=${temp%.*}
        let C$i=$temp
        echo "$line"
    done < /tmp/C_STATE

    # analyse the results
    if [ $C1 -eq 0 -a $C2 -eq 0 -a $C3 -eq 0 ]; then
        echo "FAIL:" | tee -a ${OUTPUTFILE}
        RESULT="FAIL"
    else
        echo "PASS:" | tee -a ${OUTPUTFILE}
        RESULT="PASS"
    fi
}

# ---------- Start Test -------------
echo "Test Start" | tee -a $OUTPUTFILE
[[ ! $(uname -m) =~ "86" ]] && {
    echo "The current architecture is $(uname -m). This cast just support x86 architecture!" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST SKIP
    exit 0
}

gcc -o check_platform check_platform.c
if [ $? -ne 0 ]; then
    echo "check_platform compilation fails!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

./check_platform
if [ $? -ne 0 ]; then
    echo "checking failed, platform does not support" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST SKIP
    exit 0
fi

if [ $RSTRNT_REBOOTCOUNT -eq 0 ]; then
    KERNEL=$(grubby --default-kernel)
    grubby  --update-kernel=$KERNEL --args="tsc=reliable nohz=off"
    echo "Rebooting" | tee -a $OUTPUTFILE
    rstrnt-reboot
elif [ $RSTRNT_REBOOTCOUNT -eq 1 ]; then
    runtest
elif [ $RSTRNT_REBOOTCOUNT -eq 2 ]; then
    echo "Restore cmdline configure!"
    grubby  --update-kernel=$KERNEL --remove-args="tsc=reliable nohz=off"
    echo "Testing End! Reboot system!"
    rstrnt-reboot
else
    echo "All test done!"
fi

if [ $RESULT == "PASS" ]; then
    rstrnt-report-result $TEST "PASS" 0
else
    rstrnt-report-result $TEST "FAIL" 1
fi

exit 0
