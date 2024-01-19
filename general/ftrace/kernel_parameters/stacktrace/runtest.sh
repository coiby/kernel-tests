#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

#kernel parameter to test
KPARAM="stacktrace"

FLAGDIR="/root/.kernel_parameters/${KPARAM}"
mkdir -p ${FLAGDIR}

if ! mount | grep -q debugfs ; then
    mount -t debugfs nodev /sys/kernel/debug
fi

rlJournalStart
    # Require CONFIG_STACK_TRACE=y in kernel config
    if grep --quiet "CONFIG_STACK_TRACER=y" /boot/config-$(uname -r); then
        REBOOT_FLAG=${FLAGDIR}/${KPARAM}_reboot
        CLEAN_FLAG=${FLAGDIR}/${KPARAM}_clean
        if [ -f ${REBOOT_FLAG} ] ; then
            if [ -f ${CLEAN_FLAG} ] ; then
                #continue
                echo "Test finished"
            else
                # Setup and rebooted, now it's time for check
                rlPhaseStartTest "Check ${KPARAM}"
                    rlRun -l "cat /proc/cmdline"
                    rlAssertEquals "Check ${KPARAM}" "$(cat /proc/sys/kernel/stack_tracer_enabled)" "1"
                    sleep 2
                    cat /sys/kernel/debug/tracing/stack_trace > ${KPARAM}.log
                    rlAssertGreater "At least one stacktrace line" "$(cat ${KPARAM}.log | tail -n +3 | grep -v '^#' | wc -l)" 1
                    rlFileSubmit ${KPARAM}.log
                rlPhaseEnd
                rlPhaseStartTest "Clean ${KPARAM}"
                    rlRun "grubby --update-kernel /boot/vmlinuz-$(uname -r) --remove-args '${KPARAM}'"
                    if [[ $(arch) = *s390* ]]; then
                        zipl
                    fi
                    touch ${CLEAN_FLAG}
                rlPhaseEnd
                rstrnt-reboot
            fi
        else
            # It's time for add kernel param.
            rlPhaseStartTest "Add ${KPARAM} into kernel parameter"
                rlRun "grubby --update-kernel /boot/vmlinuz-$(uname -r) --args '${KPARAM}'"
                if [[ $(arch) = *s390* ]]; then
                    zipl
                fi
                touch ${REBOOT_FLAG}
            rlPhaseEnd
            rstrnt-reboot
        fi
    else
        rlPhaseStart WARN "this case is not supported on the current architecture yet"
            grep "CONFIG_STACK_TRACE" /boot/config-$(uname -r)
            rstrnt-report-result $TEST SKIP 0
            exit 0
        rlPhaseEnd
    fi
rlJournalEnd
