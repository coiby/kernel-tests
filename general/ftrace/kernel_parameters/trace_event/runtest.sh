#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

#kernel parameter to test
KPARAM="trace_event"

#dependency kernel parameter
DEPTRACER="function"
DEPPARAM="ftrace=${DEPTRACER}"

FLAGDIR="/root/.kernel_parameters/${KPARAM}"
mkdir -p ${FLAGDIR}

if ! mount | grep -q debugfs ; then
    mount -t debugfs nodev /sys/kernel/debug
fi

rlJournalStart
    #for VALUE in $(cat /sys/kernel/debug/tracing/available_tracers) ; do
    if grep --quiet "${DEPTRACER}" /sys/kernel/debug/tracing/available_tracers; then
        VALUE="sched"
        REBOOT_FLAG=${FLAGDIR}/${VALUE}_reboot
        CLEAN_FLAG=${FLAGDIR}/${VALUE}_clean
        if [ -f ${REBOOT_FLAG} ] ; then
            if [ -f ${CLEAN_FLAG} ] ; then
                #continue
                echo "Test finished"
            else
                # Setup and rebooted, now it's time for check
                rlPhaseStartTest "Check ${KPARAM}=${VALUE}:*"
                    rlRun -l "cat /proc/cmdline"
                    rlRun -l "cat /sys/kernel/debug/tracing/set_event | grep ${VALUE}" 
                    rlRun -l "cat /sys/kernel/debug/tracing/set_event | grep -v ${VALUE}" 1
                    cat /sys/kernel/debug/tracing/trace > ${KPARAM}-${VALUE}.log
                    #rlRun -l "cat ${KPARAM}-${VALUE}.log | grep -v ${VALUE} | grep -v '#'" 1
                rlPhaseEnd
                rlPhaseStartTest "Clean ${KPARAM}=${VALUE}"
                    rlRun "grubby --update-kernel /boot/vmlinuz-$(uname -r) --remove-args '${DEPPARAM} ${KPARAM}=${VALUE}:*'"
                    if [[ $(arch) = *s390* ]]; then
                        zipl
                    fi
                    touch ${CLEAN_FLAG}
                    rlFileSubmit ${KPARAM}-${VALUE}.log
                rlPhaseEnd
                rstrnt-reboot
            fi
        else
            # It's time for add kernel param.
            rlPhaseStartTest "Add ${KPARAM}=${VALUE} into kernel parameter"
                rlRun "grubby --update-kernel /boot/vmlinuz-$(uname -r) --args '${DEPPARAM} ${KPARAM}=${VALUE}:*'"
                if [[ $(arch) = *s390* ]]; then
                    zipl
                fi
                touch ${REBOOT_FLAG}
            rlPhaseEnd
            rstrnt-reboot
        fi
    else
        rlPhaseStart WARN "this case is not supported on the current architecture yet"
            # Manual trigger a warning message by set the phase failure level to warn and make an assert error
            # rlAssertEquals "this case is not supported on the current architecture yet" 1 2
            cat /sys/kernel/debug/tracing/available_tracers
            rstrnt-report-result $TEST SKIP 0
            exit 0
        rlPhaseEnd
    fi
    #done
rlJournalEnd
