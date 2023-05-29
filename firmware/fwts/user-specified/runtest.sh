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

# source fwts include/library
. ../include/runtest.sh || exit 1

rlJournalStart
   if [[ -n $FWTSTESTS ]]; then
       rlPhaseStartSetup
       fwtsSetup
       rlPhaseEnd

       rlPhaseStartTest
       rlLog "Running fwts with these tests: $FWTSTESTS"
       rlRun "fwts $FWTSTESTS" 0,1 "run fwts with FWTSTESTS pased from beaker job"
       rlPhaseEnd

       fwtsReportResults

       rlPhaseStartCleanup
       fwtsCleanup
       rlPhaseEnd
   else
       rlFail "FWTSTESTS parameter is empty, must pass through beaker job"
   fi
rlJournalEnd
rlJournalPrintText

