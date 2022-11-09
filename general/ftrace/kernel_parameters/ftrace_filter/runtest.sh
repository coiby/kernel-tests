#!/bin/bash
# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh

#kernel parameter to test
KPARAM="ftrace_filter"

#dependency kernel parameter
DEPTRACER="function"
DEPPARAM="ftrace=${DEPTRACER}"

FLAGDIR="/root/.kernel_parameters/${KPARAM}"
mkdir -p ${FLAGDIR}

rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

if ! mount | grep -q debugfs ; then
    mount -t debugfs nodev /sys/kernel/debug
fi

rlJournalStart
    #for FILTER in $(cat /sys/kernel/debug/tracing/available_tracers) ; do
    if grep --quiet "${DEPTRACER}" /sys/kernel/debug/tracing/available_tracers; then
        if [ $rhel_major -ge 9 ]; then
            FILTER=$(cat /sys/kernel/debug/tracing/available_filter_functions | grep sched_fork | head -n 1)
        else
            FILTER=$(cat /sys/kernel/debug/tracing/available_filter_functions | grep do_fork | head -n 1)
        fi
        #if [ $(arch) == "aarch64" ]; then
        #    FILTER="_do_fork"
        #fi
        REBOOT_FLAG=${FLAGDIR}/${FILTER}_reboot
        CLEAN_FLAG=${FLAGDIR}/${FILTER}_clean
        if [ -f ${REBOOT_FLAG} ] ; then
            if [ -f ${CLEAN_FLAG} ] ; then
                #continue
                echo "Test finished"
            else
                # Setup and rebooted, now it's time for check
                rlPhaseStartTest "Check ${KPARAM}=${FILTER}"
                    rlRun -l "cat /proc/cmdline"
                    rlAssertEquals "Check ${KPARAM}" "$(cat /sys/kernel/debug/tracing/set_ftrace_filter)" "${FILTER}"
                    sleep 2
                    cat /sys/kernel/debug/tracing/trace > ${KPARAM}-${FILTER}.log
                    rlRun "cat /sys/kernel/debug/tracing/trace | grep -v '^#' | grep -v ${FILTER}" 1
                    rlRun -l "cat /sys/kernel/debug/tracing/trace | grep -v '^#' | grep ${FILTER}"
                rlPhaseEnd
                rlPhaseStartTest "Clean ${KPARAM}=${FILTER}"
                    rlRun "grubby --update-kernel /boot/vmlinuz-$(uname -r) --remove-args '${DEPPARAM} ${KPARAM}=${FILTER}'"
                    if [[ $(arch) = *s390* ]]; then
                        zipl
                    fi
                    touch ${CLEAN_FLAG}
                    rlFileSubmit ${KPARAM}-${FILTER}.log
                rlPhaseEnd
                rstrnt-reboot
            fi
        else
            # It's time for add kernel param.
            rlPhaseStartTest "Add ${KPARAM}=${FILTER} into kernel parameter"
                rlRun "grubby --update-kernel /boot/vmlinuz-$(uname -r) --args '${DEPPARAM} ${KPARAM}=${FILTER}'"
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
