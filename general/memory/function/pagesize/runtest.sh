#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm gcc
        rlShowRunningKernel
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "./pagesize"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make clean"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
