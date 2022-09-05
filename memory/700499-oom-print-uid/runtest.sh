#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Petr Benas <pbenas@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
#
#   RedHat Internal.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Check the Release Version
rlIsRHEL ">=6.2" || rlIsCentOS ">=6.2"
a=$?

if [ $a -eq 1 ]; then
    echo "Skipping test for RHEL6.2 before" | tee -a $OUTPUTFILE
    rstrnt-report-result Test_Skipped PASS 99
    exit 0
fi

rlJournalStart
    rlPhaseStartSetup
        rlRun "dmesg -c > /dev/null"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "gcc -o oomtest oomtest.c"
        rlRun "./oomtest" 0 "Running oom triggerring program"
        rlRun "dmesg | grep 'Killed process' | grep UID" 0 "we shold see UID in dmesg"
    rlPhaseEnd
rlJournalEnd
