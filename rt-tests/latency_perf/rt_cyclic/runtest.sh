#!/bin/bash

# Source rt common functions
. ../../include/runtest.sh || exit 1

rt_env_setup

export DURATION=${DURATION:-10m}
export LAT_THRES=${LAT_THRES:-40}
export SMI_THRES=${SMI_THRES:-40}
export nrcpus=$(grep -c ^processor /proc/cpuinfo)

[ -f $TEST ] && TEST="rt-tests/latency_perf/rt_cyclic"

[ ! -f $HOME/REBOOT_COUNT ] && {
    touch $HOME/REBOOT_COUNT
    echo 0 > $HOME/REBOOT_COUNT
}

function system_profile()
{
    tuned-adm profile $1 || {
        echo "profile $1 failed, please check system status." | tee -a $OUTPUTFILE
        rstrnt-report-result "system_profile" "FAIL" 1
    }
    tuned-adm active
    echo "current profile: $(tuned-adm list | grep "Current active profile" | awk -F": " '{print $2}')"
}

function runtest()
{
    echo "Measurement latency by cyclictest" | tee -a $OUTPUTFILE
    echo "Make sure test machine no SMIs issue" | tee -a $OUTPUTFILE
    hwlatdetect --duration 10m --threshold $SMI_THRES
    if [ $? -ne 0 ]; then
        echo "Test machine have the SMIs issue, please check and retry on other machine." | tee -a $OUTPUTFILE
        rstrnt-report-result "$TEST" "SKIP" 0
        exit 0
    fi
    cmdline="taskset -c $cpu_list cyclictest -m -q -p95 -D $DURATION -h40 -i 100 -t $isolate_num -a $cpu_list"
    $cmdline | tee cyclic.out
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        rstrnt-report-result "$TEST" "FAIL" 1
    else
        rstrnt-report-result "$TEST" "PASS" 0
    fi
    rstrnt-report-log -l cyclic.out

    egrep '(Min|Avg|Max) Latencies' cyclic.out | tee -a $OUTPUTFILE
}

#--- START ---#
if [ $nrcpus -lt 4 ]; then
    echo "recommend running in >= 4 CPUs machine" | tee -a $OUTPUTFILE
    rstrnt-report-result "$TEST" "SKIP" 0
    exit 0
else
    c_low=$(( nrcpus / 2 ))
    c_high=$(( nrcpus - 1 ))
    cpu_list=$c_low"-"$c_high
    isolate_num=$(( c_high - c_low + 1 ))
fi

yum install -y tuned-profiles-realtime tuned || {
    rstrnt-report-result "$TEST" "SKIP" $OUTPUTFILE
    exit 0
}

ori_profile="throughput-performance"

# use realtime profile, reboot to apply
rebootcount=$(cat $HOME/REBOOT_COUNT)
if [ $rebootcount -eq 0 ]; then
    echo "isolated_cores=$cpu_list" > /etc/tuned/realtime-variables.conf
    system_profile realtime
    echo "reboot system to apply realtime profile" | tee -a $OUTPUTFILE
    echo 1 > $HOME/REBOOT_COUNT
    rstrnt-reboot
    sleep 60; sync
elif [ $rebootcount -eq 1 ]; then
    runtest
    echo "remove realtime profile kenrel paramter and restore system profile." | tee -a $OUTPUTFILE
    system_profile $ori_profile
    echo "reboot system to restore kernel paramter" | tee -a $OUTPUTFILE
    echo 2 > $HOME/REBOOT_COUNT
    rstrnt-reboot
    sleep 60; sync
elif [ $rebootcount -eq 2 ]; then
    echo "all test done!" | tee -a $OUTPUTFILE
fi

rm -f $HOME/REBOOT_COUNT
exit 0
