#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/getnstimeofday"

function runtest()
{
    echo "### Testing start ###" | tee -a $OUTPUTFILE

    make -C ./gettime/ > /dev/null 2>&1

    insmod gettime/gettime.ko
    rmmod gettime/gettime.ko

    grep "###" /var/log/messages >> $OUTPUTFILE 

    if grep -q "test getnstimeofday() FAILED" /var/log/messages; then
        rstrnt-report-result $TEST "FAIL" 1
    else
        rstrnt-report-result $TEST "PASS" 0
    fi
}

# ---------- Start Test -------------
if [[ ! $(uname -i) =~ "86" ]]; then
    echo "The current architecture is $(uname -i), this cast just support x86 architecture!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

if [ $rhel_major -ge 8 ]; then
    pgrep chronyd > /dev/null
    RES=$?
    if [[ $RES -ne 0 ]]; then
        systemctl start chronyd
    fi
else
    pgrep ntpd > /dev/null
    RES=$?
    if [[ $RES -ne 0 ]]; then
        service ntpd start > /dev/null 2>&1
    fi
fi

runtest
exit 0
