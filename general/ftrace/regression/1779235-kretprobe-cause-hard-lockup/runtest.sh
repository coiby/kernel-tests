#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    rlPhaseStartTest
        rlRun "echo 'r:event_1 __fdget' >> /sys/kernel/debug/tracing/kprobe_events"
        rlRun "echo 'r:event_2 _raw_spin_lock_irqsave' >> /sys/kernel/debug/tracing/kprobe_events"
        rlRun "echo 1 > /sys/kernel/debug/tracing/events/kprobes/enable"
        sleep 10
        # If the test fail, system will panic. Otherwise this can be seen as pass.
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "echo 0 > /sys/kernel/debug/tracing/events/kprobes/enable"
        rlRun "echo '' > /sys/kernel/debug/tracing/kprobe_events"
    rlPhaseEnd
rlJournalEnd
