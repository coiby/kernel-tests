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
    	rlRun "fwts ebda mcfg mtrr dmar crs maxreadreq" 0,1 "run fwts tests for memory config testing"
    rlPhaseEnd
    
    fwtsReportResults
    
    rlPhaseStartCleanup
    	fwtsCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText


    	



    
