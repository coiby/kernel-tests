#!/bin/bash

# Enable TMT testing for RHIVOS
auto_include=../../../automotive/include/include.sh
[ -f $auto_include ] && . $auto_include
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0

if [ $is_rhivos -eq 1 ] ;then
# source fwts include/library for rhivos
    . ./include/include.sh || exit 1
else
# source origianl fwts include libarary
    . ../include/runtest.sh || exit 1
fi

rlJournalStart
    rlPhaseStartSetup
        if [ $is_rhivos -eq 1 ]; then
            fwtsSetupRepos
            fwtsPreSetup
            fwtsBuild
        else
            fwtsSetup
        fi
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