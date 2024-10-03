#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

KPARAM=stacktrace

rlJournalStart
    # Require CONFIG_STACK_TRACE=y in kernel config
    if stat /run/ostree-booted > /dev/null 2>&1; then
        STACK_TRACER=`grep --quiet "CONFIG_STACK_TRACER=y" /lib/modules/$(uname -r)/config`
    else
        STACK_TRACER=`grep --quiet "CONFIG_STACK_TRACER=y" /boot/config-$(uname -r)`
    fi
    if ${STACK_TRACER}; then
        declare -i already_enabled=0
        already_enabled=$(cat /proc/sys/kernel/stack_tracer_enabled)
        rlPhaseStartTest "Sanity test for ${KPARAM}"
            if [[ $already_enabled == 0 ]]; then
                rlRun "echo 1 > /proc/sys/kernel/stack_tracer_enabled"
            fi
            sleep 2
            cat /sys/kernel/debug/tracing/stack_trace > ${KPARAM}.log
            rlAssertGreater "At least one stacktrace line" "$(cat ${KPARAM}.log | tail -n +3 | grep -v '^#' | wc -l)" 1
            rlFileSubmit ${KPARAM}.log
        rlPhaseEnd
        rlPhaseStartTest "Clean ${KPARAM}"
            if [[ $already_enabled == 0 ]]; then
                rlRun "echo 0 > /proc/sys/kernel/stack_tracer_enabled"
            fi
        rlPhaseEnd
    else
        rstrnt-report-result $TEST SKIP 0
        exit 0
    fi
rlJournalEnd
