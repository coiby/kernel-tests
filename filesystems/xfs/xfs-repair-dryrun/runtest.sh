#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

    rlPhaseStartTest
        FSLIST=$(mktemp /mnt/testarea/fslist.XXXXXX)
        rlRun "findmnt --type xfs --output SOURCE --noheadings > $FSLIST" 0 "Finding XFS filesystems"
        for fs in $(cat $FSLIST) ; do
            rlRun "xfs_repair -n $fs 2>&1" 0 "xfs_repair -n $fs"
        done
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
