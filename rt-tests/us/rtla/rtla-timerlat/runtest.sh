#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rtla/rtla-timerlat"
export result_r="PASS"
export SCHED_RT_RUNTIME=$(sysctl kernel.sched_rt_runtime_us | awk -F '= ' '{print $NF}')

function check_status()
{
    if [ $? -eq 0 ]; then
        echo ":: $* :: PASS ::" | tee -a $OUTPUTFILE
    else
        result_r="FAIL"
        echo ":: $* :: FAIL ::" | tee -a $OUTPUTFILE
    fi
}

# timerlat has one thread pinned to each cpu, so the SCHED_DEADLINE admission control rejects it.
function disable_admission_control()
{
    echo "Disable the admission control" | tee -a $OUTPUTFILE
    sysctl -w kernel.sched_rt_runtime_us=-1
    check_status "Disable the admission control"
}

function restore_admission_control()
{
    echo "Restore the admission control" | tee -a $OUTPUTFILE
    if [ -n "$SCHED_RT_RUNTIME" ]; then
        sysctl -w kernel.sched_rt_runtime_us=$SCHED_RT_RUNTIME
    else
        sysctl -w kernel.sched_rt_runtime_us=950000
    fi
    check_status "Restore the admission control"
}

function skip_auto_analysis_test()
{
    if rhel_in_range 8.9 8.10 || rhel_in_range 9.3 100; then
        echo "rtla auto_analysis is only supported for RHEL >= 8.9 and >= 9.3"
        return 0
    fi
    return 1
}

function runtest()
{
    if rhel_in_range 8.8 8.10 || rhel_in_range 9.2 100; then
        echo "rtla is only supported for RHEL >= 8.8 and >= 9.2" || tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" 0
        exit 0
    fi

    echo "Package rtla-timerlat sanity test:" | tee -a $OUTPUTFILE
    rpm -q --quiet rtla || yum install -y rtla || {
        echo "Install rtla failed" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "WARN" 0
        exit 1
    }

    echo "-- rtla-timerlat: verify help page -------------------" | tee -a $OUTPUTFILE
    rtla timerlat --help
    check_status "rtla timerlat --help"

    echo "-- rtla-timerlat:  rtla-timerlat top test---------------" | tee -a $OUTPUTFILE
    rtla timerlat top -s 3 -T 10 -t
    check_status "rtla timerlat top -s 3 -T 10 -t"

    echo "-- rtla-timerlat:  rtla-timerlat top test---------------" | tee -a $OUTPUTFILE
    rtla timerlat top -P F:1 -c 0 -d 1M -q
    check_status "rtla timerlat top -P F:1 -c 0 -d 1M -q"

    echo "-- rtla-timerlat:  rtla-timerlat top test in nanoseconds---------------" | tee -a $OUTPUTFILE
    rtla timerlat top -i 2 -c 0 -n -d 30s
    check_status "rtla timerlat top -i 2 -c 0 -n -d 30s"

    if ! skip_auto_analysis_test; then
        echo "-- rtla-timerlat top: Set the automatic trace mode---------------" | tee -a $OUTPUTFILE
        rtla timerlat top -a 5  --dump-tasks
        check_status "rtla timerlat top -a 5  --dump-tasks"
    fi

    if ! skip_auto_analysis_test; then
        echo "-- rtla-timerlat top: Print the auto-analysis if hits the stop tracing condition---------------" | tee -a $OUTPUTFILE
        rtla timerlat top --aa-only 5
        check_status "rtla timerlat top --aa-only 5"
    fi

    if ! skip_auto_analysis_test; then
        echo "-- rtla-timerlat top: disable auto-analysis---------------" | tee -a $OUTPUTFILE
        rtla timerlat top -s 3 -T 10 -t --no-aa
        check_status "rtla timerlat top -s 3 -T 10 -t --no-aa"
    fi

    echo "-- rtla-timerlat:  rtla-timerlat hist test---------------" | tee -a $OUTPUTFILE
    rtla timerlat hist -c 0 -d 30s
    check_status "rtla timerlat hist -c 0 -d 30s"

    echo "-- rtla-timerlat:  rtla-timerlat hist test in nanoseconds ---------------" | tee -a $OUTPUTFILE
    rtla timerlat hist -i 2 -c 0 -n -d 30s
    check_status "rtla timerlat hist -i 2 -c 0 -n -d 30s"

    echo "-- rtla-timerlat:  rtla-timerlat hist test---------------" | tee -a $OUTPUTFILE
    disable_admission_control
    rtla timerlat hist -d 30s -c 0 -P d:100us:1ms
    check_status "rtla timerlat hist -d 30s -c 0 -P d:100us:1ms"
    restore_admission_control

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
