#!/bin/bash
# Include BeakerLib library
. /usr/share/beakerlib/beakerlib.sh || exit 1

MODULE="unexported_module"
MODFILE="${MODULE}.ko"

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest
    rlRun "make test 2>&1" 
    rlRun "dmesg > dmesg-test.log"
    rlAssertGrep "Unexported symbol" dmesg-test.log
    rlFileSubmit dmesg-test.log
    rlPhaseEnd

rlPhaseStartCleanup
        rlRun "make clean" 0 "Cleaning up"
        rlRun "rmmod $MODULE" 0-255 "Removing module if it was loaded"
    rlPhaseEnd
rlJournalEnd