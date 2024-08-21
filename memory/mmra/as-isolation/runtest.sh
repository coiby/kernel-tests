#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

export PACKAGE="${PACKAGE:-kernel}"
export TEST=as_isolation

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "gcc -o /tmp/as-isolation -D_GNU_SOURCE -lpthread as-isolation.c"
        rlRun "/tmp/as-isolation"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
