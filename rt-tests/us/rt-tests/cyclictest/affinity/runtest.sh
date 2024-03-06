#!/bin/bash

# Source rt common functions
. ../../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rt-tests/cyclictest/affinity"
export profile_file="/tmp/tuned_profile.txt"

# Test Variable
export ISOL_CPU=${ISOL_CPU:-2}

# Global Variables
export result_r="PASS"
[ -z $RSTRNT_REBOOTCOUNT ] && {
    echo "RSTRNT_REBOOTCOUNT not set - setting to 0 for manual run" | tee -a $OUTPUTFILE
    export RSTRNT_REBOOTCOUNT=0
}

function IsolateCPUs()
{
    rpm -q --quiet tuned-profiles-realtime || yum install -y tuned-profiles-realtime

    if [[ "$1" == "set" ]]; then
        declare cur_profile=$(tuned-adm active | awk -F 'profile: ' '{print $2}')
        if [ -n "$cur_profile" ]; then
            echo "Saving settings for current tuned profile ($cur_profile) to restore after test"
            echo "$cur_profile" >> $profile_file
        fi
        echo "Isolating CPU ${ISOL_CPU}:" | tee -a $OUTPUTFILE
        cp /etc/tuned/realtime-variables.conf /tmp/realtime-variables.conf.orig
        sed -i '/^isolated_cores/d' /etc/tuned/realtime-variables.conf # remove any prior isolated CPUs
        echo "isolated_cores=${ISOL_CPU}" >> /etc/tuned/realtime-variables.conf
        tuned-adm profile realtime
        tuned-adm active
    else
        echo "Removing isolated cores from realtime tuned profile" | tee -a $OUTPUTFILE
        cp /tmp/realtime-variables.conf.orig /etc/tuned/realtime-variables.conf
        if [ -f $profile_file ]; then
            declare cur_profile=$(cat $profile_file)
            tuned-adm profile $cur_profile
        else
            tuned-adm off
        fi
        tuned-adm active
    fi

    echo "Taking host down for reboot:" | tee -a $OUTPUTFILE
    rstrnt-reboot
}

function RunTest()
{
    declare pkg_name="rt-tests" && [ $rhel_x -ge 9 ] && pkg_name="realtime-tests"
    rpm -q --quiet $pkg_name || yum install -y $pkg_name
    echo "-- Begin cyclictest affinity test --" | tee -a $OUTPUTFILE

    # ----

    echo "(1) Verify that cyclictest only runs on non-isolated CPUs" | tee -a $OUTPUTFILE

    cyclictest --smp -umq -p95 1>/dev/null 2>&1 &
    sleep 5

    ps -eLo psr,args | grep cyclictest | awk '{$1=$1;print}' | grep "^$ISOL_CPU "
    if [ $? -eq 0 ]; then
        echo "cyclictest was incorrectly scheduled on isolated CPU $ISOL_CPU" | tee -a $OUTPUTFILE
        result_r="FAIL"
    fi

    pkill -9 cyclictest >/dev/null ; echo

    # ----

    echo "(2) Verify that cyclictest affinity is respected" | tee -a $OUTPUTFILE

    # randomly pick a CPU from the first node's cpulist that is not the isolated CPU
    declare affine_cpu=$(numactl --hardware | grep cpus | head -n 1 | sed "s/$ISOL_CPU//" | awk '{print $NF}')

    echo "Running cyclictest on CPU $affine_cpu" | tee -a $OUTPUTFILE
    cyclictest -a $affine_cpu -umq -p95 1>/dev/null 2>&1 &
    sleep 5

    ps -eLo psr,args | grep cyclictest | awk '{$1=$1;print}' | grep "^$affine_cpu "
    if [ $? -ne 0 ]; then
        echo "cyclictest affinity not obeyed" | tee -a $OUTPUTFILE
        result_r="FAIL"
    fi

    pkill -9 cyclictest >/dev/null ; echo

    # ---

    if [ $result_r = "PASS" ]; then
        echo "Overall result: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall result: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

# ------ Start Test --------------------------------
if rhel_in_range 0 7.8 || rhel_in_range 8.0 8.3; then
    echo "Not supported in RHEL-RT < 7.9 or RHEL-RT < 8.3 -- skipping test case" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST "SKIP" 0
    exit 0
fi

if [ $RSTRNT_REBOOTCOUNT -eq 0 ]; then
    # Initial Setup - Isolate CPUs
    IsolateCPUs "set"
elif [ $RSTRNT_REBOOTCOUNT -eq 1 ]; then
    # CPU was Isolated - run test then restore Isolated CPUs
    RunTest
    IsolateCPUs "undo"
fi
# If we get here without hitting one of the two above conditions,
# the test has already completed.  We can exit now.

exit 0
