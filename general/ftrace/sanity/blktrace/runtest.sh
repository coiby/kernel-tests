#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

#dependency kernel parameter
DEPTRACER="blk"
BOOTPART=$(mount | grep -i '/boot' | grep -v '/boot/efi'  | awk '{print $1}' | sed 's/\/dev\///')

rlJournalStart
    if grep --quiet "${DEPTRACER}" /sys/kernel/debug/tracing/available_tracers ; then
        rlPhaseStartTest "Test trace_marker"
            rlRun "echo ${DEPTRACER} > /sys/kernel/debug/tracing/current_tracer"
            rlRun "echo 1 > /sys/block/${BOOTPART//[[:digit:]]/}/${BOOTPART}/trace/enable"
            rlRun "echo > /sys/kernel/debug/tracing/trace"
            rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
            echo "test" > /boot/blktracetest
            cat /boot/blktracetest
            dd if=/dev/zero of=/boot/blktracetest bs=512k count=20
            sync
            rm /boot/blktracetest
            sleep 2
            rlRun "cat /sys/kernel/debug/tracing/trace > blktrace.log"
            rlAssertGreater "Should be more than 4 lines in blktrace log" $(cat blktrace.log | wc -l) 4
            rlFileSubmit blktrace.log
        rlPhaseEnd
        rlPhaseStartTest "Clean tracing log"
            rlRun "echo 0 > /sys/kernel/debug/tracing/tracing_on"
            rlRun "echo 'nop' > /sys/kernel/debug/tracing/current_tracer"
            rlRun "echo 0 > /sys/block/${BOOTPART//[[:digit:]]/}/${BOOTPART}/trace/enable"
            rlRun "echo > /sys/kernel/debug/tracing/trace"
        rlPhaseEnd
    else
        rlPhaseStartTest "this case is not supported on the current architecture yet"
            cat /sys/kernel/debug/tracing/available_tracers
            report_result $TEST SKIP 0
            exit 0
        rlPhaseEnd
    fi
rlJournalEnd
