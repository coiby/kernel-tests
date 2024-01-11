#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/libcmd.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "change_and_verify ${CMDLINEARGS}"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
