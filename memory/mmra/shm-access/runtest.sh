#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../cki_lib/libcki.sh

export PACKAGE="${PACKAGE:-kernel}"
export TEST=shm-access
export OUTPUTFILE=""

if cki_is_qm; then
    TMPDIR=$(mktemp -d /var/tmp/log.XXX)
    OUTPUTFILE=$TMPDIR/outputfile.log
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        UserHome=""
        rlLog "Create non-root user"
        if cki_is_qm; then
           rlRun "UserHome=$(mktemp -d /var/home.XXX)" 0 "Creating testuser home dir"
           rlRun "adduser -d ${UserHome}/testuser -p '' testuser"
        else
           rlRun "adduser testuser"
        fi
        rlLog "Create shared memory segment"
        rlRun "gcc -o /tmp/shm-create -D_GNU_SOURCE shm-create.c"
        rlRun "gcc -o /tmp/shm-create-posix -DUSE_POSIX_INTERFACE -D_GNU_SOURCE shm-create.c"
    rlPhaseEnd
    rlPhaseStartTest "Create shared memory segments"
        rlRun "/tmp/shm-create create"
        rlRun "/tmp/shm-create-posix create"
    rlPhaseEnd
    rlPhaseStartTest "Access shm with non-root user, assert segment content"
        rlRun "gcc -o /tmp/shm-access -D_GNU_SOURCE shm-access.c"
        rlRun "su testuser -c /tmp/shm-access" 1,139
        rlRun "/tmp/shm-create read"
    rlPhaseEnd
    rlPhaseStartTest "Access shm with non-root user, assert segment content - use POSIX interface"
        rlRun "gcc -o /tmp/shm-access-posix -DUSE_POSIX_INTERFACE -D_GNU_SOURCE shm-access.c"
        rlRun "su testuser -c /tmp/shm-access-posix" 1,139
        rlRun "/tmp/shm-create-posix read"
    rlPhaseEnd
    rlPhaseStartTest "Run shm-create-posix delete"
        rlRun "/tmp/shm-create-posix delete"
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "userdel -rf testuser"
        rlRun "ipcrm --shmem-key 0xDEADBEEF"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
