#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm gcc
        rlShowRunningKernel
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "./kernel-64k"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make clean"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
