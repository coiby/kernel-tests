#! /bin/bash -x

. ../../../cki_lib/libcki.sh || exit 1

TEST="general/time/clock_getres"
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

function runtest ()
{
    # Running the getres
    ./clock_getres
    if [ $? -ne 0 ]; then
        echo "clock_getres() test FAIL" >>$OUTPUTFILE 2>&1
        rstrnt-report-result $TEST "FAIL" 1
    else
        echo "clock_getres() test PASS" >>$OUTPUTFILE 2>&1
        rstrnt-report-result $TEST "PASS" 0
    fi
}

# ---------- Start Test -------------

gcc -o clock_getres clock_getres.c -lrt
if [ $? -ne 0 ]; then
    echo "clock_getres.c compilation fails!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

if [ $rhel_major -lt 8 ]; then
    service ntpd stop >& /dev/null
    runtest
    service ntpd start >& /dev/null
else
    systemctl stop chronyd >& /dev/null
    runtest
    systemctl start chronyd >& /dev/null
fi
exit 0
