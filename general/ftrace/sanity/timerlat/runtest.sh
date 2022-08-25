#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    if grep --quiet timerlat /sys/kernel/debug/tracing/available_tracers; then
    rlPhaseStartTest "timerlat tracer sanity test"
        rlRun "echo 0 > /sys/kernel/debug/tracing/tracing_on"
        rlRun "echo > /sys/kernel/debug/tracing/trace"
        rlRun "echo 'timerlat' > /sys/kernel/debug/tracing/current_tracer"
        rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
        sleep 3
        rlRun -l "cat /sys/kernel/debug/tracing/trace > trace.log"
        rlAssertGreater "Should be more than 3 lines in trace.log" $(grep 'timer_latency' trace.log | wc -l) 3
        rlFileSubmit trace.log
        rlRun "echo 0 > /sys/kernel/debug/tracing/tracing_on"
        rlRun "echo 'nop' > /sys/kernel/debug/tracing/current_tracer"
        rlRun "echo > /sys/kernel/debug/tracing/trace"
    rm -f *.log
    rlPhaseEnd
    else
    rlPhaseStartTest "timerlat tracer is not supported on this kernel"
        rlLogWarning "timerlat is not supported"
        cat /sys/kernel/debug/tracing/available_tracers
    rlPhaseEnd
    fi
rlJournalEnd
