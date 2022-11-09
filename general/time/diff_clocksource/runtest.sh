#! /bin/bash -x

. ../../../cki_lib/libcki.sh || exit 1

TEST="general/time/diff_clocksource"

function runtest ()
{
    # Disable timedifftest-qa test.  This is known failure in RHEL5.
    # Fix for this issue is significant and would require medium code
    # change - see BZs 250708 and 4611184.

    echo "***** Start gtod_backwards *****" | tee -a $OUTPUTFILE
    J=0
    while [ $J -lt 100 ]; do
        J=`expr $J + 1`
        echo "***** loop number $J *****" | tee -a $OUTPUTFILE
        ./different-clock-source.sh 2>&1 | tee -a $OUTPUTFILE
    done

    ./analyse-result.sh

    if grep -q 'Failed:' $OUTPUTFILE; then
        echo "Time test Failed:" >>$OUTPUTFILE 2>&1
        rstrnt-report-result $TEST "FAIL" 1
    else
        echo "Time test Passed:" >>$OUTPUTFILE 2>&1
        rstrnt-report-result $TEST "PASS" 0
    fi
}

# ---------- Start Test -------------
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

gcc -o gettimeofday gettimeofday.c
if [ $? -ne 0 ]; then
    echo "gettimeofday compilation fails!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

if [ $rhel_major -ge 8 ]; then
    systemctl stop chronyd >& /dev/null
    runtest
    systemctl start chronyd >& /dev/null
else
    service ntpd stop >& /dev/null
    runtest
    service ntpd start >& /dev/null
fi

exit 0
