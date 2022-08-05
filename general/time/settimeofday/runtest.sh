#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/settimeofday"

function runtest()
{
    echo "***** Start settimeofday *****" | tee -a $OUTPUTFILE
    J=0
    while [ $J -lt 10 ]; do
        echo "***** Start loop number $J *****" | tee -a $OUTPUTFILE
        ./settimeofday 2>&1 | tee -a $OUTPUTFILE
        J=`expr $J + 1`
    done

    if grep "PASS" $OUTPUTFILE; then
        rstrnt-report-result $TEST "PASS" 0
    else
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

# ---------- Start Test -------------
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

gcc -o settimeofday settimeofday.c

if [ $rhel_major -ge 8 ]; then
    systemctl stop chronyd
    runtest
    systemctl start chronyd
else
    service ntpd stop >& /dev/null
    runtest
    service ntpd start >& /dev/null
fi

exit 0
