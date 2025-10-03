#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest "Ensure qcom_scm loads"
        rlRun "journalctl -k | grep 'qcom_scm firmware:scm: assigned reserved memory node.*'"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
