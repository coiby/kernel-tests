#!/bin/bash

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../kernel-include/runtest.sh || exit 1

function add_aboot_param ()
{
    current_aboot_cmdline=$(abootimg -i /boot/aboot-"${K_VER}"-"${K_REL}"."$(arch)".img | awk  '/cmdline/ {print}' | cut -f 4-"$NR" -d ' ')
    if [ -n "${current_aboot_cmdline}" ]; then
        current_aboot_cmdline+=" "
        current_aboot_cmdline+="${CMDLINEARGS}"
    else
        current_aboot_cmdline+="${CMDLINEARGS}"
    fi
    rlRun "abootimg -u /boot/aboot-${K_VER}-${K_REL}.$(arch).img -c cmdline='${current_aboot_cmdline}'"
    rlRun "dd if=/boot/aboot-${K_VER}-${K_REL}.$(arch).img of=/dev/disk/by-partlabel/boot_a"
    rlRun "sync"
}
function remove_aboot_param ()
{
    # shellcheck disable=SC2207
    current_aboot_cmdline=($(abootimg -i /boot/aboot-"${K_VER}"-"${K_REL}"."$(arch)".img | awk  '/cmdline/ {print}' | cut -f 4-"$NR" -d ' '))
    if [ -z "${current_aboot_cmdline[0]}" ]; then
        rlLog "WARNING: Unable to find parameter in the allowed list."
        rlPhaseEnd
        rlJournalEnd
        rlJournalPrintText
        exit 0
    else
        for i in "${!current_aboot_cmdline[@]}"; do
            if echo "${CMDLINEARGS##-}" | grep -q "${current_aboot_cmdline[${i}]}"; then
                rlRun "unset current_aboot_cmdline[${i}]"
            fi
        done
        # want to keep spaces as delimiter
        # shellcheck disable=SC2124
        new_aboot_cmdline="${current_aboot_cmdline[@]}"
        rlRun "abootimg -u /boot/aboot-${K_VER}-${K_REL}.$(arch).img -c cmdline='${new_aboot_cmdline}'"
        rlRun "dd if=/boot/aboot-${K_VER}-${K_REL}.$(arch).img of=/dev/disk/by-partlabel/boot_a"
        rlRun "sync"
    fi
}
function change_cmdline ()
{
    rlLog "Old cmdline:"
    rlRun "cat /proc/cmdline"

    # Update the boot loader.
    default=$(/sbin/grubby --default-kernel)

    # If the first character is - in the arguments, we remove them from
    # the kernel commandline.
    if echo "${CMDLINEARGS}" | grep -q "^-"; then
        rlLog "Cmdline to be removed: ${CMDLINEARGS##-}"
        if [ -e /sys/devices/soc0/machine ]; then
            rlRun "remove_aboot_param"
        elif [ -e /run/ostree-booted ]; then
            rlRun "rpm-ostree kargs --delete-if-present='${CMDLINEARGS##-}' --import-proc-cmdline"
        else
            rlRun "/sbin/grubby --remove-args='${CMDLINEARGS##-}' --update-kernel='${default}'"
        fi
    else
        rlLog "Cmdline to be added: ${CMDLINEARGS}"
        if [ -e /sys/devices/soc0/machine ]; then
            rlRun "add_aboot_param"
        elif [ -e /run/ostree-booted ]; then
            rlRun "rpm-ostree kargs --append-if-missing='${CMDLINEARGS##-}' --import-proc-cmdline"
        else
            rlRun "/sbin/grubby --args='${CMDLINEARGS}' --update-kernel='${default}'"
        fi
    fi

    # Once more change to s390 and s390x.
    if [ "$(arch)" = "s390" ] || [ "$(arch)" = "s390x" ]; then
        /sbin/zipl
    fi

    rlLog "Reboot now!"
    rlRun "rstrnt-reboot"
}

function verify_cmdline ()
{
    rlLog "New cmdline:"
    rlRun "cat /proc/cmdline"

    if echo "${CMDLINEARGS}" | grep -q "^-"; then
        # shellcheck disable=SC2016
        rlRun '! grep -q "${CMDLINEARGS##-}" /proc/cmdline'
    else
        # shellcheck disable=SC2016
        rlRun 'grep -q "${CMDLINEARGS}" /proc/cmdline'
    fi

    rlLog "Successful end of test."
}
rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest
        if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then
            # Prepare for the first reboot.
            rlRun "change_cmdline"
        else
            # The reboot has finished. Verify the cmdline.
            rlRun "verify_cmdline"
        fi
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
