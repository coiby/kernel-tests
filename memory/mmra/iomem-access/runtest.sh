#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../cki_lib/libcki.sh

export PACKAGE="${PACKAGE:-kernel}"
export TEST=iomem-access

OUTPUTFILE=""

if cki_is_qm; then
    TMPDIR=$(mktemp -d /var/tmp/log.XXX)
    OUTPUTFILE=$TMPDIR/outputfile.log
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        UserHome=""
        if cki_is_qm; then
           rlRun "UserHome=$(mktemp -d /var/home.XXX)" 0 "Creating testuser home dir"
           rlRun "adduser -d ${UserHome}/testuser -p '' testuser"
        else
           rlRun "adduser testuser"
        fi
        DEVICE=serial
        START_ADDR=$(cat /proc/iomem | grep $DEVICE | head -n1 | cut -d'-' -f1)
        END_ADDR=$(cat /proc/iomem | grep $DEVICE | head -n1 | cut -d'-' -f2 | cut -d':' -f1)
        if [[ -z $START_ADDR || -z $END_ADDR ]]; then
            rlRun "userdel -rf testuser"
            rlLogError "Device $DEVICE not found."
            exit 1
        fi
    rlPhaseEnd
    rlPhaseStartTest "Write to a memory mapped device"
        rlLog "Device under test is $DEVICE, start_addr=$START_ADDR, end_addr=$END_ADDR"
        rlRun "gcc -o /tmp/iomem-access -D_GNU_SOURCE iomem-access.c"
        rlLog "Switch to non-root user and attempt to access device memory range. Expect open to fail or process to be terminated with SIGSEGV."
        rlRun "su testuser -c '/tmp/iomem-access $START_ADDR $END_ADDR'" 1,139
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "userdel -rf testuser"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
