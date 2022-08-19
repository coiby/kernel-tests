#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    rlPhaseStartTest
        rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
        rlRun "cat /sys/kernel/debug/tracing/available_events > /sys/kernel/debug/tracing/set_event"
    rlPhaseEnd
rlJournalEnd
