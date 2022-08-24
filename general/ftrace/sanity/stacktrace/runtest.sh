#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

KPARAM=stacktrace

rlJournalStart
    # Require CONFIG_STACK_TRACE=y in kernel config
    if grep --quiet "CONFIG_STACK_TRACER=y" /boot/config-$(uname -r); then
        rlPhaseStartTest "Sanity test for ${KPARAM}"
            rlRun "echo 1 > /proc/sys/kernel/stack_tracer_enabled"
            sleep 2
            cat /sys/kernel/debug/tracing/stack_trace > ${KPARAM}.log
            rlAssertGreater "At least one stacktrace line" "$(cat ${KPARAM}.log | tail -n +3 | grep -v '^#' | wc -l)" 1
            rlFileSubmit ${KPARAM}.log
        rlPhaseEnd
        rlPhaseStartTest "Clean ${KPARAM}"
            rlRun "echo 0 > /proc/sys/kernel/stack_tracer_enabled"
        rlPhaseEnd
    else
        rstrnt-report-result $TEST SKIP 0
        exit 0
    fi
rlJournalEnd
