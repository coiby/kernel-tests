#!/bin/bash
# Include beakerlib
. /usr/share/beakerlib/beakerlib.sh || exit 1

if stat /run/ostree-booted > /dev/null 2>&1; then
    rpm -q binutils || rpm-ostree install -A --idempotent --allow-inactive binutils
else
    rpm -q binutils || yum install -y binutils
fi

rlJournalStart
    rlPhaseStartTest
        mkdir -p overlay/{lower,upper,work,merge}
        cd overlay/
        mount -t overlay overlay -o lowerdir=lower,upperdir=upper,workdir=work merge
        cp $(which true) merge/
        addr1=$(readelf -h merge/true | grep Entry)
        addr=${addr1:(-4)}
        rlRun -l "echo \"p:true_entry $(pwd)/merge/true:0x${addr}\" > /sys/kernel/debug/tracing/uprobe_events"
        rlRun -l "echo 1 > /sys/kernel/debug/tracing/events/uprobes/true_entry/enable"
        rlRun -l "dmesg | tail"
        rlRun -l "dmesg | tail | grep true_entry | grep 'not enable'" 1-255
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "echo 0 > /sys/kernel/debug/tracing/events/uprobes/true_entry/enable"
        rlRun "echo '' > /sys/kernel/debug/tracing/uprobe_events"
        rlRun "umount merge"
    rlPhaseEnd
rlJournalEnd
