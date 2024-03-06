#!/bin/bash
# Include BeakerLib library
. /usr/share/beakerlib/beakerlib.sh || exit 1

MODULE="unexported_module"
MODFILE="${MODULE}.ko"

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    # rlPhaseStart
    #     # rlRun "make" 2 "-p 'File doesn't link as expected'"
    #     rlRun "make"
    # rlPhaseEnd

    # rlPhaseStart
    #     rlRun "make" 0-255
    #     if [ -f $MODFILE ]; then
    #         rlRun "insmod $MODFILE" 1 "Loading the module should fail."
    #         rlRun "dmesg | grep -i 'unresolved symbol'" 0 "Checking dmesg for unresolved symbol error"
    #     else
    #         rlLogInfo "Module file does not exist. Linking step failed as expected."
    #     fi
    # rlPhaseEnd
    rlPhaseStart "Compilation"
    if ! make; then
        rlPass "Compilation failed as expected due to unresolved symbols"
    fi
    rlRun "insmod $MODFILE" 1 "Loading the module should fail."
    rlRun "dmesg | grep -i 'unresolved symbol'" 0 "Checking dmesg for unresolved symbol error"
    rlPhaseEnd

rlPhaseStartCleanup
        rlRun "make clean" 0 "Cleaning up"
        rlRun "rmmod $MODULE" 0-255 "Removing module if it was loaded"
    rlPhaseEnd
rlJournalEnd