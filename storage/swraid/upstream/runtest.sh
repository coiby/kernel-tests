#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh

function run_test()
{
    rlRun "git clone git://git.kernel.org/pub/scm/utils/mdadm/mdadm.git"
    cd mdadm || exit 1

    rlRun "make everything"

    [ -a tests/00linear ] && rlRun "./test --tests=00linear"
    [ -a tests/06name ] && rlRun "./test --tests=06name"
}

rlJournalStart
    rlPhaseStartTest
        rlRun "dmesg -C"
        rlRun "uname -a"
        rlLog "$0"
        run_test
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
