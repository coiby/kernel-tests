#!/bin/bash

# Enable TMT testing for RHIVOS
auto_include=../../../automotive/include/rhivos.sh
[ -f $auto_include ] && . $auto_include
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0

# Include rhts environment
if ! (($is_rhivos)); then
    . /usr/bin/rhts-environment.sh || exit 1
fi

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1


. ../include/runtest.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        fwtsSetup
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Running the following fwts tests: $(fwts --utils --show-tests)"
        rlRun "fwts --utils" 0,1 "run fwts utils tests"
    rlPhaseEnd

    fwtsReportResults

    rlPhaseStartCleanup
        fwtsCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText