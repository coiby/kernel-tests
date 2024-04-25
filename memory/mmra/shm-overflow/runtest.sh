#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

export TEST=shm-overflow

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest "Write outside shared memory segment"
        rlRun "gcc -o /tmp/shm-overflow -D_GNU_SOURCE shm-overflow.c"
        rlRun "/tmp/shm-overflow"
    rlPhaseEnd
    rlPhaseStartTest "Write outside shared memory segment - POSIX interface"
        rlRun "gcc -o /tmp/shm-overflow-posix -DUSE_POSIX_INTERFACE -D_GNU_SOURCE shm-overflow.c"
        rlRun "/tmp/shm-overflow-posix"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
