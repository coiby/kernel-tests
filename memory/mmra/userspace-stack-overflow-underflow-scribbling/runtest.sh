#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlRun "tmp=\$(mktemp -d)" 0 "Create tmp directory"
        # do not follow set inside the string, disable the warning
        # shellcheck disable=SC2154
        rlRun "cp Makefile stackman.c stacklib.c stacklib.h $tmp"
        rlRun "pushd $tmp"
        rlRun "set -o pipefail"
        rlRun "make" 0 "Compile stack manipuation program"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "script -O output.log -c \"./stackman overflow 2>&1\"" 0 "Run overflow program (SEGFAULT expected)"
        rlAssertGrep "Segmentation fault" "output.log"
        rlAssertGrep "COMMAND_EXIT_CODE=\"139\"" "output.log"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "script -O output.log -c \"./stackman underflow 2>&1\"" 0 "Run underflow program (SEGFAULT expected)"
        rlAssertGrep "Segmentation fault" "output.log"
        rlAssertGrep "COMMAND_EXIT_CODE=\"139\"" "output.log"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "script -O output.log -c \"./stackman scribbling 2>&1\"" 0 "Run scribbling program (SEGFAULT expected)"
        rlAssertGrep "Segmentation fault" "output.log"
        rlAssertGrep "COMMAND_EXIT_CODE=\"139\"" "output.log"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $tmp" 0 "Remove tmp directory"
    rlPhaseEnd
rlJournalEnd
