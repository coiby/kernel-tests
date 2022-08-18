#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    rlPhaseStartTest
        # Workaround OOM
        for pid in $(pgrep beah) $(pgrep rhts) $(pgrep ltp) $(pgrep dhclient) $(pgrep NetworkManager); do
            echo -16 > /proc/$pid/oom_adj
        done
        # make sure children of this process are not protected
        # as those include also OOM tests
        echo 0 > /proc/self/oom_adj
        rlRun "dmesg -C"
        rlRun "echo 10 > /sys/kernel/debug/tracing/buffer_size_kb"
        rlRun "echo 8556384240 > /sys/kernel/debug/tracing/buffer_size_kb" 0-255
        rlRun "dmesg &> 1339451-dmesg.log"
        rlRun "grep WARNING 1339451-dmesg.log | grep 'ring_buffer.c'" 1
        rlRun "echo 10 > /sys/kernel/debug/tracing/buffer_size_kb"
        rlFileSubmit 1339451-dmesg.log
        rlRun "dmesg -C"
    rlPhaseEnd
rlJournalEnd
