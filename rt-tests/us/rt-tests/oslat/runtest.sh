#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rt-tests/oslat"

: "${LATCHECK:=1}"
: "${MAXLAT:=150}"
: "${RUN_TIME:=10m}"
export LATCHECK MAXLAT RUN_TIME
export rhel_x

function oslat_skip_checks()
{
    # only run in RHEL-8.3+
    if rhel_in_range 0 8.2; then
        echo "oslat available in RHEL-8.3+ only - skipping" | tee -a $OUTPUTFILE
        rstrnt-report-result "${TEST}/rhel_version_check" "SKIP" 0
        exit 0
    fi

    if [ "$(nproc --all)" -eq 1 ]; then
        echo "System requires at least 2 CPUs to run oslat case (bz1837816)"
        rstrnt-report-result "${TEST}/only-1-CPU" "SKIP" 0
        exit 0
    fi
}

function oslat_setup()
{
    # get the isolated CPU list after applying realtime tuned profile
    cpu_list="$(get_isolated_cores)"
    # if no CPUs were isolated, only use half the system's CPUs for the test
    if [[ -z $cpu_list ]]; then
        nrcpus=$(grep -c ^processor /proc/cpuinfo)
        c_low=$(( nrcpus / 2 ))
        c_high=$(( nrcpus - 1 ))
        cpu_list="${c_low}-${c_high}"
        echo "= Using CPUs ${cpu_list} as no cores have been isolated, and" | tee -a $OUTPUTFILE
        echo "= running oslat on all CPUs tends to hang the system." | tee -a $OUTPUTFILE
    fi

    duration_flag="--duration" && oslat --help | grep -q '\-\-runtime' && duration_flag="--runtime"

    # ps -axo pid,cmd,ni,%cpu,pri,rtprio --> get process rtprio valule
    # assign oslat process on 1 numa node to stablilize latency
    if [[ $(rpm -qf "/boot/vmlinuz-$(uname -r)") =~ kernel-rt ]]; then
        oslat_cmd="oslat --cpu-list ${cpu_list} --rtprio 1 ${duration_flag} ${RUN_TIME}"
    else
        oslat_cmd="oslat --cpu-list ${cpu_list} ${duration_flag} ${RUN_TIME}"
    fi
}

function measure_oslat_latency()
{
    # run stalld to prevent a CPU self-detected call trace
    stalld -t 30 -k || {
        echo "stalld start failed - aborting test" | tee -a $OUTPUTFILE
        rstrnt-report-result "${TEST}/stalld-start" "FAIL" 1
        exit 1
    }

    # show kernel cmdline
    tee -a $OUTPUTFILE < /proc/cmdline

    # run the oslat cmd
    rm -f oslat.log
    $oslat_cmd | tee oslat.log
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "oslat command failed" | tee -a $OUTPUTFILE
        rstrnt-report-result "${TEST}/oslat_cmd" "FAIL" 1
        return
    fi

    # kill stalld process after oslat completion
    pkill stalld

    # get and report max latency
    max_latency=$(grep "Maximum" oslat.log | tr ' ' '\n' | grep -E "[0-9]+" | awk '$0>x {x=$0}; END{print x}')
    rstrnt-report-log -l oslat.log
    rstrnt-report-result "${TEST}/oslat_cmd" "PASS" 0

    # if LATCHECK=1, check if latency exceed threshold
    if [[ "$LATCHECK" == 1 ]]; then
        if [[ "$max_latency" -le "$MAXLAT" ]]; then
            echo "Max latency $max_latency <= $MAXLAT" | tee -a $OUTPUTFILE
            rstrnt-report-result "${TEST}/latency_under_threshold" "PASS" "$max_latency"
        else
            echo "Max latency $max_latency > $MAXLAT" | tee -a $OUTPUTFILE
            rstrnt-report-result "${TEST}/latency_under_threshold" "FAIL" "$max_latency"
        fi
    fi
}

function run_test ()
{
    oslat_setup
    measure_oslat_latency
    echo "Test End Time: $(date)" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST "PASS" 0
}

# ---------- Start Test -------------
oslat_skip_checks

if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    echo "Test Start Time: $(date)" | tee -a $OUTPUTFILE

    declare pkg_name="rt-tests" && [ $rhel_x -ge 9 ] && pkg_name="realtime-tests"
    rpm -q --quiet $pkg_name || yum install -y $pkg_name

    if ! which oslat; then
        echo "No oslat binary found" | tee -a $OUTPUTFILE
        rstrnt-report-result "${TEST}/oslat_available" "FAIL" 1
        exit 1
    fi

    rt_env_setup
    enable_tuned_realtime
fi

run_test
exit 0
