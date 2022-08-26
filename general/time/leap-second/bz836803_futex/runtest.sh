#!/bin/bash

TEST="general/time/leap-second/bz836803_futex"

function runtest()
{
    # Just run
    ./leap-a-day -s -i 10 | tee -a $OUTPUTFILE

    grep -q "Note: hrtimer early expiration failure observed" $OUTPUTFILE || RC=$?

    if [[ $RC -eq 0 ]];then
        echo "FAIL:" | tee -a ${OUTPUTFILE}
        rstrnt-report-result $TEST "FAIL" 1
    else
        echo "PASS:" | tee -a ${OUTPUTFILE}
        rstrnt-report-result $TEST "PASS" 0
    fi
}

## clone upstream repo
#echo "Checking out upstream timetests tree"
#git clone git://github.com/johnstultz-work/timetests.git
#[ $? -ne 0 ] && report_result FAIL
#echo "Compiling timetests"
#make -C timetests
#cp timetests/leap-a-day ./leap-a-day
#[ $? -ne 0 ] && report_result FAIL
gcc leap-a-day.c -o leap-a-day -lrt

service ntpd stop >& /dev/null
[ -e /usr/bin/systemctl ] && $(/usr/bin/systemctl stop chronyd >& /dev/null)
runtest
service ntpd start>& /dev/null
[ -e /usr/bin/systemctl ] && $(/usr/bin/systemctl start chronyd >& /dev/null)
exit 0
