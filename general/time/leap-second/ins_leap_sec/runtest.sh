#!/bin/bash

# Include cki library
. ../../../../cki_lib/libcki.sh || exit 1

TEST="general/time/leap-second/ins_leap_sec"

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

    if [ $? -eq 0 ]; then
        rstrnt-report-result $TEST "PASS" 0
    else
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

echo '
This case insert leap second repeatedly until system power off
Run this case before your own tests
Do not enable ntp or chrony during your tests
'
# compile leap-a-day.c
gcc leap-a-day.c -o leap-a-day -lrt || {
    echo "compile leap-a-day.c failed"
    rstrnt-report-result $TEST "FAIL" 1
    exit 1
}

/usr/bin/systemctl stop chronyd >& /dev/null
runtest
/usr/bin/systemctl start chronyd >& /dev/null
exit 0
