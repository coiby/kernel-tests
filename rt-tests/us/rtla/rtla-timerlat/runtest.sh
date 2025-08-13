#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rtla/rtla-timerlat"
export SCHED_RT_RUNTIME=$(sysctl kernel.sched_rt_runtime_us | awk -F '= ' '{print $NF}')

# timerlat has one thread pinned to each cpu, so the SCHED_DEADLINE admission control rejects it.
# restore the param after the timerlat test.
function restore_admission_control()
{
    if [ -n "$SCHED_RT_RUNTIME" ]; then
        sysctl -w kernel.sched_rt_runtime_us=$SCHED_RT_RUNTIME
    else
        sysctl -w kernel.sched_rt_runtime_us=950000
    fi
}

function skip_auto_analysis_test()
{
    if rhel_in_range 0 8.8 || rhel_in_range 9.0 9.2; then
        log "rtla auto_analysis is only supported for RHEL >= 8.9 and >= 9.3"
        return 0
    fi
    return 1
}

function runtest()
{
    if rhel_in_range 0 8.7 || rhel_in_range 9.0 9.1; then
        rstrnt-report-result "rtla timerlat is only supported for RHEL >= 8.8 and >= 9.2" "SKIP" 0
        exit 0
    fi

    oneliner "yum install -y rtla"

   # verify help page
    oneliner "rtla timerlat --help"
    # rtla-timerlat top test: verify -s/--stack
    oneliner "rtla timerlat top -s 3 -T 10 -t -d 30s"
    # rtla-timerlat top test: verify -P/--priority
    oneliner "rtla timerlat top -P F:1 -c 0 -d 1M -q"
    # rtla-timerlat top test in nanoseconds
    oneliner "rtla timerlat top -i 2 -c 0 -n -d 30s"

    if ! skip_auto_analysis_test; then
        # rtla-timerlat top: Set the automatic trace mode
        oneliner "rtla timerlat top -a 5 --dump-tasks"
        # Print the auto-analysis if hits the stop tracing condition
        oneliner "rtla timerlat top --aa-only 5"
        # disable auto-analysis
        oneliner "rtla timerlat top -s 3 -T 10 -t --no-aa"
    fi

    # rtla-timerlat hist test: verify -c/--cpus
    oneliner "rtla timerlat hist -c 0 -d 30s"

    # rtla-timerlat hist test in nanoseconds
    oneliner "rtla timerlat hist -i 2 -c 0 -n -d 30s"

    phase_start_test "rtla-timerlat hist test: verify -P/--priority"
    run "sysctl -w kernel.sched_rt_runtime_us=-1" 0 "verify the disabled admission control"
    run "rtla timerlat hist -d 30s -c 0 -P d:100us:1ms"
    run "restore_admission_control"
    phase_end
}

if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    rt_env_setup
    enable_tuned_realtime
fi

runtest
exit 0
