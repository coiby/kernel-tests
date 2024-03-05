#!/bin/bash

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../cki_lib/libcki.sh || exit 1

function add_aboot_param()
{
    CMDLINEARGS="$1"
    current_aboot_cmdline=$(abootimg -i /boot/aboot-"$(uname -r)".img | awk  '/cmdline/ {print}' | cut -f 4-"$NR" -d ' ')
    if [ -n "${current_aboot_cmdline}" ]; then
        current_aboot_cmdline+=" "
        current_aboot_cmdline+="${CMDLINEARGS}"
    else
        current_aboot_cmdline+="${CMDLINEARGS}"
    fi
    abootimg -u /boot/aboot-"$(uname -r)".img -c cmdline="${current_aboot_cmdline}" || exit 1
    dd if=/boot/aboot-"$(uname -r)".img of=/dev/disk/by-partlabel/boot_a || exit 1
    sync
}
function remove_aboot_param()
{
    CMDLINEARGS="$1"
    # shellcheck disable=SC2207
    current_aboot_cmdline=($(abootimg -i /boot/aboot-"$(uname -r)".img | awk  '/cmdline/ {print}' | cut -f 4-"$NR" -d ' '))
    if [ -z "${current_aboot_cmdline[0]}" ]; then
        echo "WARNING: Unable to find parameter in the allowed list."
        exit 0
    else
        for i in "${!current_aboot_cmdline[@]}"; do
            if echo "${CMDLINEARGS##-}" | grep -q "${current_aboot_cmdline[${i}]}"; then
               # shellcheck disable=SC2184
               unset current_aboot_cmdline["${i}"]
            fi
        done
        # want to keep spaces as delimiter
        # shellcheck disable=SC2124
        new_aboot_cmdline="${current_aboot_cmdline[@]}"
        abootimg -u /boot/aboot-"$(uname -r)".img -c cmdline="${new_aboot_cmdline}" || exit 1
        dd if=/boot/aboot-"$(uname -r)".img of=/dev/disk/by-partlabel/boot_a || exit 1
        sync
    fi
}
function change_cmdline()
{
    CMDLINEARGS="$1"
    echo "Old cmdline:"
    cat /proc/cmdline

    # Update the boot loader.
    default=$(/sbin/grubby --default-kernel)

    # If the first character is - in the arguments, we remove them from
    # the kernel commandline.
    if echo "${CMDLINEARGS}" | grep -q "^-"; then
        echo "Cmdline to be removed: ${CMDLINEARGS##-}"
        if cki_is_abd; then
            remove_aboot_param "${CMDLINEARGS}"
        elif [ -e /run/ostree-booted ]; then
            rpm-ostree kargs --delete-if-present="${CMDLINEARGS##-}" --import-proc-cmdline
        else
            /sbin/grubby --remove-args="${CMDLINEARGS##-}" --update-kernel="${default}"
        fi
    else
        echo "Cmdline to be added: ${CMDLINEARGS}"
        if cki_is_abd; then
            add_aboot_param "${CMDLINEARGS}"
        elif [ -e /run/ostree-booted ]; then
            rpm-ostree kargs --append-if-missing="${CMDLINEARGS##-}" --import-proc-cmdline
        else
            /sbin/grubby --args="${CMDLINEARGS}" --update-kernel="${default}"
        fi
    fi

    # Once more change to s390 and s390x.
    if [ "$(arch)" = "s390" ] || [ "$(arch)" = "s390x" ]; then
        /sbin/zipl
    fi

    echo "Need to reboot before changes take effect."
}

function verify_cmdline()
{
    CMDLINEARGS="$1"
    echo "New cmdline:"
    cat /proc/cmdline

    if echo "${CMDLINEARGS}" | grep -q "^-"; then
        ! grep -q "${CMDLINEARGS##-}" /proc/cmdline && return 0
    else
        grep -q "${CMDLINEARGS}" /proc/cmdline && return 0
    fi

    return 1
}
function change_and_verify(){
    if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then
        # Prepare for the first reboot.
        change_cmdline "${CMDLINEARGS}"
        rstrnt-reboot
    else
        # The reboot has finished. Verify the cmdline.
        verify_cmdline "${CMDLINEARGS}"
    fi
}
