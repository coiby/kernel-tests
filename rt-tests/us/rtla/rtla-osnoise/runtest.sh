#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rtla/rtla-osnoise"
export result_r="PASS"

rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')
rhel_minor=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $2}')
export rhel_major rhel_minor

function check_status()
{
    if [ $? -eq 0 ]; then
        echo ":: $* :: PASS ::" | tee -a $OUTPUTFILE
    else
        result_r="FAIL"
        echo ":: $* :: FAIL ::" | tee -a $OUTPUTFILE
    fi
}

function runtest()
{
    # rtla supports from 8.8 and 9.2
    if ! ( (( "$rhel_major" == 8 && "$rhel_minor" >= 8 )) || (( "$rhel_major" == 9 && "$rhel_minor" >=2 )) || (( "$rhel_major" >= 10 ))); then
        echo "rtla is only supported for RHEL >= 8.8 and >= 9.2" || tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" 0
        exit 0
    fi

    echo "Package rtla-osnoise sanity test:" | tee -a $OUTPUTFILE
    rpm -q --quiet rtla || yum install -y rtla || {
        echo "Install rtla failed" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "WARN" 0
        exit 1
    }

    echo "-- rtla-osnoise: verify help page -------------------" | tee -a $OUTPUTFILE
    rtla osnoise --help
    check_status "rtla osnoise --help"

    echo "-- rtla-osnoise:  rtla-osnoise top test---------------" | tee -a $OUTPUTFILE
    rtla osnoise top -P F:1 -c 0 -r 900000 -d 1M -q
    check_status "rtla osnoise top -P F:1 -c 0 -r 900000 -d 1M -q"

    echo "-- rtla-osnoise:  rtla-osnoise top test---------------" | tee -a $OUTPUTFILE
    rtla osnoise top -s 30 -T 1 -t
    check_status "rtla osnoise top -s 30 -T 1 -t"

    echo "-- rtla-osnoise:  rtla-osnoise hist test---------------" | tee -a $OUTPUTFILE
    rtla osnoise hist -s 30 -T 1 -t
    check_status "rtla osnoise hist -s 30 -T 1 -t"

    echo "-- rtla-osnoise:  rtla-osnoise hist test---------------" | tee -a $OUTPUTFILE
    rtla osnoise hist -P F:1 -c 0 -r 900000 -d 1M -b 10 -E 25
    check_status "rtla osnoise hist -P F:1 -c 0 -r 900000 -d 1M -b 10 -E 25"

    if [ $result_r = "PASS" ]; then
        echo "Overall result: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall result: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    rt_env_setup
    enable_tuned_realtime
fi

runtest
exit 0
