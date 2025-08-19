#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

LTP_VERSION=${LTP_VERSION:-20250530}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        # Check if version ok else use default.
        if wget -q https://raw.githubusercontent.com/linux-test-project/ltp/refs/tags/${LTP_VERSION}/runtest/syscalls ; then
            rlLog "https://raw.githubusercontent.com/linux-test-project/ltp/refs/tags/${LTP_VERSION}/runtest/syscalls downloaded"
        else
            LTP_VERSION=20250530
            rlLog "Could not find version supplied using https://raw.githubusercontent.com/linux-test-project/ltp/refs/tags/${LTP_VERSION}/runtest/syscalls for test."
            wget -q https://raw.githubusercontent.com/linux-test-project/ltp/refs/tags/${LTP_VERSION}/runtest/syscalls
        fi
        rlRun "cp syscalls syscalls2"
        rlRun "cat syscalls >> syscalls2"
        rlRun "cat syscalls >> syscalls2"
        rlRun "cat syscalls >> syscalls2"
        rlRun "sort syscalls2 > syscalls.sorted"
        rlRun "sed -i '/^$/d' syscalls.sorted"
        rlRun "sed -i '/^#/d' syscalls.sorted"
        rlRun "cp syscalls.sorted ../../distribution/ltp/generic/configs/SYSCALLS"
        if [[ -e patches/syscalls.${LTP_VERSION}.patch ]]; then
            rlRun "patch ../../distribution/ltp/generic/configs/SYSCALLS patches/syscalls.${LTP_VERSION}.patch"
        fi
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
