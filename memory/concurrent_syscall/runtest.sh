#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

LTP_VERSION=${LTP_VERSION:-20250130}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        rlRun "wget https://gitlab.com/redhat/centos-stream/tests/ltp/-/raw/${LTP_VERSION}/runtest/syscalls -O ../../distribution/ltp/generic/configs/SYSCALLS"
    rlPhaseEnd
    rlPhaseStartTest "Concurrent execution"
        rlRun "pushd ../../distribution/ltp/generic"
        rlRun "./runtest.sh"
        rlRun "grep -B 5 Distribution /mnt/testarea/SYSCALLS.log > ${TMT_PLAN_DATA}/concurrent_syscalls.log"
        rlAssertGrep "failed.* 0$" ${TMT_PLAN_DATA}/concurrent_syscalls.log
        rlAssertGrep "broken.* 0$" ${TMT_PLAN_DATA}/concurrent_syscalls.log
        rlAssertGrep "warnings.* 0$" ${TMT_PLAN_DATA}/concurrent_syscalls.log
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
