#!/bin/bash

. ../../../../cki_lib/libcki.sh || exit 1

TEST="general/time/leap-second/ins_leap_sec_once"
RESULT="PASS"

function runtest ()
{
    echo "Running leap-a-day test"
    # insert a leap second one time, and reset the time to within
    # 10 seconds of midnight UTC.
    if [ -n "$NOSETTIME" ]; then
        nohup ./leap-a-day &
    else
        nohup ./leap-a-day -s &
    fi
    ./leap-a-day -s -i 1 | tee -a $OUTPUTFILE
    if ! grep -q TIME_WAIT $OUTPUTFILE; then
        RESULT="FAIL"
        rstrnt-report-result $TEST $RESULT 1
    else
        RESULT="PASS"
        rstrnt-report-result $TEST $RESULT 0
    fi
    killall leap-a-day
}

echo '
This case insert leap second repeatedly until system power off
Run this case before your own tests
Do not enable ntp or chrony during your tests
'
# compile leap-a-day.c
gcc leap-a-day.c -o leap-a-day -lrt || {
    echo "compile failed"
    rstrnt-report-result $TEST "FAIL" 1
    exit 1
}

# disable ntpd or chronyd and run the test, RHEL6 EOL.
# In rhel6 or old system, ntpd
# In rhel7 or new system, chronyd
/usr/bin/systemctl stop chronyd >& /dev/null
runtest
/usr/bin/systemctl start chronyd >& /dev/null
exit 0
