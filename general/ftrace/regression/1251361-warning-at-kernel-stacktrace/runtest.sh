#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    rlPhaseStartSetup
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "rpm-ostree install -A --idempotent --allow-inactive trace-cmd"
        else
            if (type dnf &>/dev/null); then
                rlRun "dnf install -y trace-cmd"
            else
                rlRun "yum install -y trace-cmd"
        fi
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "echo stacktrace > /sys/kernel/debug/tracing/trace_options"
        rlRun "echo \"p kfree\" >> /sys/kernel/debug/tracing/kprobe_events"
        rlRun "echo \"r exit_mmap\" >> /sys/kernel/debug/tracing/kprobe_events"
        rlRun "echo 1 > /sys/kernel/debug/tracing/events/kprobes/enable"
        rlRun "echo 1 >/sys/kernel/debug/tracing/tracing_on"
        rlRun "dmesg | egrep 'WARN|save_stack_trace_regs'" 1
    rlPhaseEnd
    rlPhaseStartCleanup
        trace-cmd reset
    rlPhaseEnd
rlJournalEnd
