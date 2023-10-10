#!/bin/bash

# include beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart


ANALYZE_SUSPEND=analyze_suspend.py
LOOKASIDE=${LOOKASIDE:-http://download.devel.redhat.com/qa/rhts/lookaside/}

rlPhaseStartSetup
    rlLog "Getting ${ANALYZE_SUSPEND} source"
    rlRun "wget ${LOOKASIDE}/${ANALYZE_SUSPEND}" 0 "Downloading analyze_suspend source"
rlPhaseEnd

rlPhaseStartTest
    rlRun "python analyze_suspend.py -modes" 0 "Supported suspend modes"
    rlRun "python analyze_suspend.py -status" 0 "Feature requirement status"
    rlRun "python analyze_suspend.py -config config/standby.cfg" 0 "S1: Test suspend to standby"
    rlRun "python analyze_suspend.py -config config/freeze.cfg" 0 "S2: Test suspend to idle"
    rlRun "python analyze_suspend.py -config config/suspend.cfg" 0 "S3: Test suspend to mem"
    rlRun "python analyze_suspend.py -config config/hibernate.cfg" 0 "S4: Test suspend to disk"
rlPhaseEnd

rlPhaseStartCleanup
    rhts-submit-log -l standby*/*.txt
    rhts-submit-log -l freeze*/*.txt
    rhts-submit-log -l suspend*/*.txt
    rhts-submit-log -l hibernate*/*.txt
    rlRun "/rm -Rf standby-*" 0 "Removing logs"
    rlRun "/rm -Rf freeze-*" 0 "Removing logs"
    rlRun "/rm -Rf suspend-*" 0 "Removing logs"
    rlRun "/rm -Rf hibernated-*" 0 "Removing logs"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
