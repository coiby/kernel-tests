#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlRun "echo setup..."
        pin_mem_limit="$(ulimit -l)"
        rlRun "echo $pin_mem_limit"
        rlRun "ulimit -l unlimited"
        rlRun "ulimit -l"
        rlRun "TESTTMPDIR=$(mktemp -d)"
        rlRun "cp Makefile test_mmra_resident_memory.c $TESTTMPDIR"
        rlRun "pushd $TESTTMPDIR"
        rlRun "set -o pipefail"
        rlRun "make"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "echo test resident_memory starts..."
        rlRun "./test_mmra_resident_memory"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "echo cleanup"
        rlRun "ulimit -l $pin_mem_limit"
        rlRun "ulimit -l"
        rlRun "popd"
        rlRun "rm -r $TESTTMPDIR"
    rlPhaseEnd
rlJournalEnd
