#!/bin/bash

. ../../../cki_lib/libcki.sh || exit 1

TEST="general/time/check_freq_ced"

function runtest ()
{
    # checking the clock event device event_handler
    COUNT=`cat /proc/timer_list  | grep "event_handler"  | cut -d ' ' -f 4 | wc -l`
    LAPIC=`expr $COUNT - 1`
    i=0
    cat /proc/timer_list  | grep "event_handler"  | cut -d ' ' -f 4 > /tmp/TIMER_LIST
    while read line
    do
        ((i++))
        if [ $i == 1 ];then
            Global_Event_Handler=$line
        else
            Lapic_Event_Handler=$line
        fi
    done < /tmp/TIMER_LIST

    Global_Event_Device=`cat /proc/timer_list  | grep "Clock Event Device" | cut -d ' ' -f 4 | sed -n 1p`
    Local_Event_Device="lapic"

    echo ">>> The Global Clock Event Device is $Global_Event_Device  Handler is -> $Global_Event_Handler" | tee -a $OUTPUTFILE
    echo ">>> The  Local Clock Event Device is $Local_Event_Device  Handler is -> $Lapic_Event_Handler" | tee -a $OUTPUTFILE

    case $Lapic_Event_Handler in
        hrtimer_interrupt)
            echo "### It is high resolution mode ###" | tee -a $OUTPUTFILE
            ./check_tick_freq | tee /tmp/HRES
            HZ=`cat /tmp/HRES | sed -n 1p  | cut -d ' ' -f 7`
            RES=`echo "$HZ <= 1010" | bc`
            if [ $RES == 1 ];then
                rstrnt-report-result $TEST "FAIL" 1
            else
                rstrnt-report-result $TEST "PASS" 0
            fi
            ;;
        tick_handle_periodic | tick_nohz_handler)
            echo "### It is low resolution mode ###"
            ./check_tick_freq | tee /tmp/LOWRES
            HZ=`cat /tmp/LOWRES | sed -n 1p  | cut -d ' ' -f 7`
            RES=`echo "$HZ > 1010" | bc`
            if [ $RES == 1 ];then
                rstrnt-report-result $TEST "FAIL" 1
            else
                rstrnt-report-result $TEST "PASS" 0
            fi
            ;;
        *)
            echo "No support event" | tee -a $OUTPUTFILE
            rstrnt-report-result $TEST "SKIP" 0
            ;;
    esac
}

# ---------- Start Test -------------
[[ ! $(uname -m) =~ "86" ]] && {
    echo "Only support x86 arch, skip~" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST "SKIP" 0
    exit 0
}

gcc -o check_tick_freq check_tick_freq.c
if [ $? -ne 0 ]; then
    echo "check_tick_freq compilation fails!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

runtest
exit 0
