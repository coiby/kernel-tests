#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

export TEST="rt-tests/us/rt-setup/sanity"
export result_r="PASS"
export rhel_x

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
    echo "Package rt-setup sanity test:" | tee -a $OUTPUTFILE

    echo "-- run rt-setup -------------------------------" | tee -a $OUTPUTFILE
    if [ $rhel_x -ge 9 ]; then
        /usr/bin/realtime-setup
    else
        /usr/bin/rt-setup
    fi
    check_status "rt-setup"

    echo "-- turn off cpu_partial processing ------------" | tee -a $OUTPUTFILE
    /usr/bin/slub_cpu_partial_off
    check_status "slub_cpu_partial_off"
    declare cpupart=$(cat /sys/kernel/slab/*/cpu_partial | sort | uniq)
    [[ "$cpupart" == "0" ]]
    check_status "/sys/kernel/slab/*/cpu_partial == 0"

    echo "-- kernel-is-rt -------------------------------" | tee -a $OUTPUTFILE
    /usr/sbin/kernel-is-rt
    check_status "kernel-is-rt"

    echo "-- enable net-socket timestamp ----------------" | tee -a $OUTPUTFILE
    if [ $rhel_x -ge 9 ]; then
        systemctl restart realtime-entsk
    else
        systemctl restart rt-entsk
    fi
    check_status "systemctl restart rt-entsk"
    if [ $rhel_x -ge 9 ]; then
        systemctl status realtime-entsk | grep "active (running)"
    else
        systemctl status rt-entsk | grep "active (running)"
    fi
    check_status "rt-entsk.service is active (running)"

    echo "-- verify realtime group exists ---------------" | tee -a $OUTPUTFILE
    grep 'realtime' /etc/group
    check_status "grep realtime /etc/group"

    echo "-- verify realtime.conf exists ----------------" | tee -a $OUTPUTFILE
    [ -f /etc/security/limits.d/realtime.conf ]
    check_status "/etc/security/limits.d/realtime.conf exists"

    echo "-- user in realtime group test ----------------" | tee -a $OUTPUTFILE
    if grep 'realuser:' /etc/passwd ; then
        userdel realuser
        rm -rf /home/realuser
    fi
    useradd -G realtime realuser
    su - realuser -c "sleep 1d &"
    declare sleep_pid=$(pgrep -f 'sleep 1d')
    declare nice_limit=$(grep nice /etc/security/limits.d/realtime.conf | awk '{print $4}')
    su - realuser -c "renice -n ${nice_limit} -p ${sleep_pid}"
    check_status "realtime user can renice based on realtime.conf limits"
    kill -9 $sleep_pid ; wait $sleep_pid 2>/dev/null

    if [ $result_r = "PASS" ]; then
        echo "Overall result: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall result: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

runtest
exit 0
