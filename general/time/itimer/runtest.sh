#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/itimer"

function runtest()
{
    count=1

    while [ $count -lt 360 ]
    do
        printf "\nTesting Count : $count\n"
        ./general_itimer | tee -a $OUTPUTFILE
        RES=$?
        if [ $RES != 0 ];then
            echo "!!!!!! FAIL !!!!!!" | tee -a $OUTPUTFILE
            rstrnt-report-result $TEST "FAIL" 1
            exit 1
        fi
        ((count++))
    done

    printf "Testing PASS\n" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST "PASS" 0
}

# ---------- Start Test -------------
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

gcc -o general_itimer general_itimer.c -lrt

if (type systemctl); then
    systemctl stop chronyd
    runtest
    systemctl start chronyd
else
    service ntpd stop >& /dev/null
    runtest
    service ntpd start>& /dev/null
fi

exit 0
