#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    rlPhaseStartSetup
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "rpm-ostree install -A --idempotent --allow-inactive trace-cmd"
        else
            rlRun "yum install trace-cmd -y"
        fi
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
        rlRun "echo \"comm == modprobe || comm == insmod\" > /sys/kernel/debug/tracing/events/kmem/filter"
        rlRun "trace-cmd stat | egrep 'comm == modprobe|comm == insmod'"
    rlPhaseEnd
    rlPhaseStartCleanup
        trace-cmd reset
    rlPhaseEnd
rlJournalEnd
