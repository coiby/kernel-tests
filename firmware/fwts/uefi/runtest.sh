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
        rlRun "modinfo efi_runtime" 0 "This should show efi_runtime is built/installed, if not uefi tests will not work"
        UNSAFETESTS="$(fwts --unsafe --show-tests | tail -n +2 | cut -d ' ' -f 2 | tr '\n' ',')"
        rlLog "Running the following fwts tests: $(fwts --uefitests --show-tests)"
        if [ "$(uname -m)" = "aarch64" ]; then
            rlLog "Skipping the following UNSAFE fwts tests: $UNSAFETESTS"
            SKIPTESTS="--skip-test=$UNSAFETESTS"
        else
            rlLog "Attempting to run the following UNSAFE fwts tests: $UNSAFETESTS"
        fi
        rlRun "fwts --uefitests $SKIPTESTS" 0 "run fwts UEFI tests"
    rlPhaseEnd

    fwtsReportResults

    rlPhaseStartCleanup
        fwtsCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText

