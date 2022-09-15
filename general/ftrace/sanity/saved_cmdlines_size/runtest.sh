#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh
# This will execute only when saved_cmdlines_size exists.
# This verifies bug 1117093

rlJournalStart
    if [ -f /sys/kernel/debug/tracing/saved_cmdlines_size ]; then
    rlPhaseStartTest "Testing saved_cmdlines_size"
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rpm-ostree -A --idempotent --allow-inactive install trace-cmd
        else
            yum install -y trace-cmd
        fi
        trace-cmd reset
        rlRun "echo 1 > /sys/kernel/debug/tracing/events/enable"
        rlRun "echo 128 > /sys/kernel/debug/tracing/saved_cmdlines_size"
        rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
        ls > /dev/null
        sleep 2
        rlRun "echo 0 > /sys/kernel/debug/tracing/tracing_on"
        rlRun -l "trace-cmd stat" 0-255
        rlAssertGreater "Should show more than 6 lines including comments and <idle>" $(cat /sys/kernel/debug/tracing/trace | tee save1.log | grep -v '^$' | awk '{print $1}' | awk -F '-' '{print $1}' | sort | uniq | wc -l) 6
        cat save1.log | awk '{print $1}' | awk -F '-' '{print $1}' | sort | uniq > filtered1.log
        rlRun -l "cat filtered1.log" 0-255
        rlRun "echo 1024 > /sys/kernel/debug/tracing/saved_cmdlines_size"
        rlRun "echo > /sys/kernel/debug/tracing/trace"
        rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
        sleep 2
        ls > /dev/null
        rlRun "echo 0 > /sys/kernel/debug/tracing/tracing_on"
        rlRun -l "trace-cmd stat" 0-255
        rlAssertGreater "Should show more than 6 events" $(cat /sys/kernel/debug/tracing/trace | tee save2.log | grep -v '^$' | awk '{print $1}' | awk -F '-' '{print $1}' | sort | uniq | wc -l) 6
        cat save2.log | awk '{print $1}' | awk -F '-' '{print $1}' | sort | uniq > filtered2.log
        rlRun -l "cat filtered2.log" 0-255
        rlFileSubmit save1.log
        rlFileSubmit save2.log
        trace-cmd reset
    rlPhaseEnd
    else
        rlLogWarning "/sys/kernel/debug/tracing/saved_cmdlines_size does not exist!"
        cat /sys/kernel/debug/tracing/available_tracers
    fi
rlJournalEnd
