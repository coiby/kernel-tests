#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    if [ -f /sys/kernel/tracing/events/csd/enable ]; then
    rlPhaseStartTest "csd tracepoint test"
        rlRun "ls /sys/kernel/debug/tracing/events/csd/"
        rlRun "trace-cmd record -e csd_function_entry -e csd_function_exit -e csd_queue_cpu sleep 10"
        rlRun "trace-cmd report  -i trace.dat | tee csd.log"
        rlAssertGreater "Should have a few instance of csd_* trace" $(grep 'csd_function' csd.log | wc -l) 1
        rlFileSubmit csd.log
    rlPhaseEnd
    else
    rlPhaseStartTest "No CSD tracepoint on current system"
        rlLog "SKIP: CSD tracepoints backport since RHEL9.5"
        rstrnt-report-result "trace_csd" "SKIP"
    rlPhaseEnd
    fi
rlJournalEnd
