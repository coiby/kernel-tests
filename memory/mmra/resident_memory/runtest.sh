#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup "setup..."
        pin_mem_limit="$(ulimit -l)"
        rlLog "$pin_mem_limit"
        rlRun "ulimit -l unlimited"
        rlRun "ulimit -l"
        rlRun "TESTTMPDIR=$(mktemp -d)"
        rlRun "cp Makefile test_mmra_resident_memory.c $TESTTMPDIR"
        rlRun "pushd $TESTTMPDIR"
        rlRun "set -o pipefail"
        rlRun "make"
    rlPhaseEnd

    rlPhaseStartTest "test resident_memory starts..."
        rlRun "script -O output.log -c \"./test_mmra_resident_memory>&1\"" 0 "Run test_mmra_resident_memory"
        rlAssertGrep "SUCCESS: requested 1024 KiB, pre-allocated [[:digit:]]* KiB, locked 1024 KiB" "output.log"
    rlPhaseEnd

    rlPhaseStartCleanup "cleanup..."
        rlRun "ulimit -l $pin_mem_limit"
        rlRun "ulimit -l"
        rlRun "popd"
        rlRun "rm -r $TESTTMPDIR"
    rlPhaseEnd
rlJournalEnd
