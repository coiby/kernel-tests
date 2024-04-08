#!/bin/bash

. ../../../../cki_lib/libcki.sh || exit 1

TEST="general/time/leap-second/leap_hrtimer"
RESULT="PASS"

function runtest ()
{
    echo "List current clocksource" | tee -a "$OUTPUTFILE"
    echo "$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)" | tee -a "$OUTPUTFILE"

    J=0
    while [ "$J" -lt 500 ]; do
        bash ./hrtimer_on_each_CPU.sh
        J=`expr "$J" + 1`
        echo "count $J:" | tee -a "$OUTPUTFILE"
        ./leap_second
        sleep 10
        killall hrtimer
        ./check_hrtimer_exprie_ontime
        RC=$?
        if [ $RC -ne 0 ];then
            RESULT="FAIL"
            break
        fi
    done

    if [ "$RESULT" = "FAIL" ]; then
        rstrnt-report-result $TEST "$RESULT" 1
    else
        echo "kernel no livelock panic" | tee -a "$OUTPUTFILE"
        rstrnt-report-result $TEST "$RESULT" 0
    fi
}

# compile
gcc -o hrtimer hrtimer.c
gcc -o leap_second leap_second.c
gcc -o check_hrtimer_exprie_ontime check_hrtimer_exprie_ontime.c -pthread -lrt

# disable ntpd or chronyd and run the test, RHEL6 EOL.
# In rhel6 or old system, ntpd
# In rhel7 or new system, chronyd
/usr/bin/systemctl stop chronyd >& /dev/null
runtest
/usr/bin/systemctl start chronyd >& /dev/null
exit 0
