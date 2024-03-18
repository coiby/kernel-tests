#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        rlLog "Create non-root user"
        rlRun "adduser testuser"
        rlLog "Create shared memory segment"
        rlRun "gcc -o /tmp/shm-create -D_GNU_SOURCE shm-create.c"
        rlRun "/tmp/shm-create create"
    rlPhaseEnd
    rlPhaseStartTest "Access shm with non-root user, assert segment content"
        rlRun "gcc -o /tmp/shm-access -D_GNU_SOURCE shm-access.c"
        rlRun "su testuser -c /tmp/shm-access" 1,139
        rlRun "/tmp/shm-create read"
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "userdel -rf testuser"
        rlRun "ipcrm --shmem-key 0xDEADBEEF"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
