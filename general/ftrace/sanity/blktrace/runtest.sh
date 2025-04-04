#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

#dependency kernel parameter
DEPTRACER="blk"
mountpoint -q /boot
mflag=$?
if [ $mflag -ne 0 ]; then
    TESTPART=$(mount | grep '/[[:space:]]' | awk '{print $1}' | sed 's/\/dev\///')
    MOUNTPOINT="/root"
else
    TESTPART=$(mount | grep -i '/boot' | grep -v '/boot/efi'  | awk '{print $1}' | sed 's/\/dev\///')
    MOUNTPOINT="/boot"
fi

# Add/fix 3 special case support:
# a. the "/[[:digit:]]/" will delete number from nvme device name, like nvme0n1
# b. if the mount point is LVM, device mapper, then use the lsscsi to get the device name
# c. some device are not belong to HDD and SSD
dflag=$(lsscsi -w)
if [[ -z "$dflag" ]]; then
    DEVICE_NAME=$(lsblk -d -o name | sed -n '2p')
else
    DEVICE_NAME=$(lsscsi -w | awk -F' ' '{print $NF}' | awk -F'/' '{print $3}')
    if [ $(echo $DEVICE_NAME | wc -w) -gt 1 ]; then
        for i in $DEVICE_NAME; do
            if [[ "$TESTPART" =~ $i ]]; then
                DEVICE_NAME="$i"
                break;
            fi
        done
    fi
    # If scsci device does not match test partition name then
    # device may not be scsi. Find device name from partition.
    if [ $(echo $DEVICE_NAME | wc -w) -gt 1 ]; then
        DEVICE_NAME=$(lsblk -no pkname /dev/${TESTPART})
    fi
fi

rlJournalStart
    if grep --quiet "${DEPTRACER}" /sys/kernel/debug/tracing/available_tracers ; then
        rlPhaseStartTest "Test trace_marker"
            rlRun "echo ${DEPTRACER} > /sys/kernel/debug/tracing/current_tracer"
            rlRun "echo 1 > /sys/block/${DEVICE_NAME}/${TESTPART}/trace/enable"
            rlRun "echo > /sys/kernel/debug/tracing/trace"
            rlRun "echo 1 > /sys/kernel/debug/tracing/tracing_on"
            echo "test" > $MOUNTPOINT/blktracetest
            cat $MOUNTPOINT/blktracetest
            dd if=/dev/zero of=/boot/blktracetest bs=512k count=20
            sync
            rm -f $MOUNTPOINT/blktracetest
            sleep 2
            rlRun "cat /sys/kernel/debug/tracing/trace > blktrace.log"
            rlAssertGreater "Should be more than 4 lines in blktrace log" $(cat blktrace.log | wc -l) 4
            rlFileSubmit blktrace.log
        rlPhaseEnd
        rlPhaseStartTest "Clean tracing log"
            rlRun "echo 0 > /sys/kernel/debug/tracing/tracing_on"
            rlRun "echo 'nop' > /sys/kernel/debug/tracing/current_tracer"
            rlRun "echo 0 > /sys/block/${DEVICE_NAME}/${TESTPART}/trace/enable"
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
