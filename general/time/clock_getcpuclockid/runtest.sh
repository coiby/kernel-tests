#! /bin/bash -x

. ../../../cki_lib/libcki.sh || exit 1

TEST="general/time/clock_getcpuclockid"
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

function runtest ()
{
    # Running the getcpclockid
    ./clock_getcpuclockid
    if [ $? -ne 0 ]; then
        echo "clock_getcpuclockid() test FAIL" >>$OUTPUTFILE 2>&1
        rstrnt-report-result $TEST "FAIL" 1
    else
        echo "clock_getcpuclockid() test PASS" >>$OUTPUTFILE 2>&1
        rstrnt-report-result $TEST "PASS" 0
    fi
}

# ---------- Start Test -------------

gcc -o clock_getcpuclockid clock_getcpuclockid.c -lrt
if [ $? -ne 0 ]; then
    echo "clock_getcpuclockid.c compilation fails!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

if ! (type systemctl); then
    service ntpd stop >& /dev/null
    runtest
    service ntpd start >& /dev/null
else
    systemctl stop chronyd >& /dev/null
    runtest
    systemctl start chronyd >& /dev/null
fi

exit 0
