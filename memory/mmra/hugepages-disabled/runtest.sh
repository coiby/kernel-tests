#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartTest
        rlRun "echo test hugepages disabled starts..."
        # Start Test

        # Check that hugepages are disabled as expected, if found fail
        rlAssertNotGrep "hugetlbfs" "/proc/filesystems"

    rlPhaseEnd
rlJournalEnd
