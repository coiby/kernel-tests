#!/bin/bash

# Source rt common functions
. ../../include/runtest.sh || exit 1

rt_env_setup

export runtime=${runtime:-5m}
export LAT_THRES=${LAT_THRES:-40}
export nrcpus rhel_x

[ -f $TEST ] && TEST="rt-tests/latency_perf/oslat_valid"

[ ! -f $HOME/REBOOT_COUNT ] && {
    touch $HOME/REBOOT_COUNT
    echo 0 > $HOME/REBOOT_COUNT
}


function system_profile()
{
    tuned-adm profile $1 || {
        echo "profile $1 failed, please check system status."
        rstrnt-report-result "system_profile" "FAIL" 1
    }
    tuned-adm active
    echo "current profile: $(tuned-adm list | grep "Current active profile" | awk -F": " '{print $2}')"
}

function runtest()
{
    # clone oslat program from github. (after 8.3 ES3, oslat built in rt-tests package)
    if [ $rhel_x -ge 9 ]; then
        dnf install -y realtime-tests stalld
    else
        dnf install -y rt-tests
        dnf install -y stalld
        if [ $? -ne 0 ] ; then
            echo "Unable to install stalld, RHEL version likely too low" | tee -a $OUTPUTFILE
            rstrnt-report-result "$TEST" "SKIP" 0
            exit 0
        fi

    fi

    declare duration_flag="--duration" && oslat --help | grep -q '\-\-runtime' && duration_flag="--runtime"

    # ps -axo pid,cmd,ni,%cpu,pri,rtprio --> get process rtprio valule
    if [[ $(rpm -qf "/boot/vmlinuz-$(uname -r)") =~ kernel-rt ]]; then
        oslat_cmd="oslat --cpu-list ${cpu_list} --rtprio 1 ${duration_flag} ${runtime}"
    else
        oslat_cmd="oslat --cpu-list ${cpu_list} ${duration_flag} ${runtime}"
    fi

    # due to oslat will cause CPU self-detected call trace, use stalld to avoid this stall
    # stalld bug on rhel9: bzXXXXXX
    stalld -t 30 -k || {
        echo "stalld start failed, may have some system stall"
        rstrnt-report-result "stalld-start" "FAIL" 1
    }

    # show kernel cmdline
    tee -a $OUTPUTFILE < /proc/cmdline

    # take the media latency in a single time
    $oslat_cmd | tee tmp.log | tee -a oslat.log
    maxlat=$(grep "Maximum" tmp.log | tr ' ' '\n' | grep -E "[0-9]+" | awk '$0>x {x=$0}; END{print x}')
    echo $maxlat | tee -a max_latency.log
    rstrnt-report-log -l oslat.log
    rstrnt-report-log -l max_latency.log
    # median=$((10#${median}))

    # Don't do latency checking
    # if [ $(echo "$median >= $LAT_THRES"|bc) = 1 ]; then
    #     rstrnt-report-result "median-latency" "FAIL" 1
    # else
    #     rstrnt-report-result "median-latency" "PASS" 0
    # fi

    # kill stalld process after oslat
    pkill stalld
}

#---- START -------#
if [ $nrcpus -lt 4 ]; then
    echo "recommend running oslat in >= 4 CPUs machine" | tee -a $OUTPUTFILE
    rstrnt-report-result "$TEST" "SKIP" 0
    exit 0
else
    c_low=$(( nrcpus / 2 ))
    c_high=$(( nrcpus - 1 ))
    cpu_list=$c_low"-"$c_high
fi

# install all necessary packages
dnf install -y tuned-profiles-realtime tuned git gcc make numactl-devel numactl-libs numactl || {
    rstrnt-report-result "$TEST" "FAIL" 1
    exit 1
}

# the default profile is throughput-performance, revert after all test
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
    # after all test done, move back
    # rt_args=$(cat /etc/tuned/bootcmdline | grep TUNED_BOOT_CMDLINE | awk -F'"' '{print $2}')
    # grubby --remove-args="$rt_args" --update-kernel=DEFAULT
    system_profile $ori_profile
    echo "reboot system to restore kernel paramter" | tee -a $OUTPUTFILE
    echo 2 > $HOME/REBOOT_COUNT
    rstrnt-reboot
    sleep 60; sync
elif [ $rebootcount -eq 2 ]; then
    echo "all test done!" | tee -a $OUTPUTFILE
    rstrnt-report-result "$TEST" "PASS" 0
fi

rm -f $HOME/REBOOT_COUNT
exit 0
