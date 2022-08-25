#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
   if grep --quiet hwlat /sys/kernel/debug/tracing/available_tracers; then
    rlPhaseStartTest "hwlat tracer sanity test"
        rlRun "echo 'hwlat' > /sys/kernel/debug/tracing/current_tracer"
        rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
        rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_thresh"
        sleep 1
        rlRun -l "cat /sys/kernel/debug/tracing/trace > trace.log"
        rlRun -l "grep 'tracer: hwlat' trace.log"
    rlPhaseEnd
    else
    rlPhaseStartTest "hwlat tracer is not supported on this kernel"
        rlLogWarning "hwlat is not supported"
        cat /sys/kernel/debug/tracing/available_tracers
    rlPhaseEnd
    fi
rlJournalEnd
