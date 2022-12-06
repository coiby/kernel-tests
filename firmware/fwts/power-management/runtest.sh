#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# source fwts include/library
. ../include/runtest.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        fwtsSetup
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Running the following fwts tests: $(fwts --power-states --show-tests)"
        rlRun "fwts --power-states" 0,1 "run fwts power management tests"
    rlPhaseEnd

    fwtsReportResults

    rlPhaseStartCleanup
        fwtsCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText

