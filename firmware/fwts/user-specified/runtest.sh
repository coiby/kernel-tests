#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
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


    	



    
