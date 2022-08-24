#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

uname -r
rlJournalStart
    for CLOCK in $(cat /sys/kernel/debug/tracing/trace_clock) ; do
        rlPhaseStartTest "Check ${CLOCK} trace clock"
            rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
            rlRun "echo wakeup > /sys/kernel/debug/tracing/current_tracer"
            rlRun "echo ${CLOCK//[\[\]]} > /sys/kernel/debug/tracing/trace_clock"
            ls &> /dev/null
            rlRun "cat /sys/kernel/debug/tracing/trace_clock | grep '[${CLOCK//[\[\]]}]'"
            #rlAssertEquals "Check current tracer" "$(cat /sys/kernel/debug/tracing/trace_clock)" "[${CLOCK//[\[\]]}]" 
            rlRun "echo 0 > /sys/kernel/debug/tracing/tracing_on"
            rlRun "echo > /sys/kernel/debug/tracing/trace"
        rlPhaseEnd
    done
    echo "local" > /sys/kernel/debug/tracing/trace_clock
rlJournalEnd
