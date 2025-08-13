#!/bin/bash

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../cki_lib/libcki.sh || exit 1

function remove_default_args()
{
    local CMDLINEARGS=(${1})

    for i in "${!CMDLINEARGS[@]}"; do
        if [[ "androidboot" == "${CMDLINEARGS[${i}]/.*}" ]]; then
            unset "CMDLINEARGS[${i}]"
        fi
        if [[ "silent_boot" == "${CMDLINEARGS[${i}]/.*}" ]]; then
            unset "CMDLINEARGS[${i}]"
        fi
        if [[ "bootconfig" == "${CMDLINEARGS[${i}]}" ]]; then
            unset "CMDLINEARGS[${i}]"
        fi
    done
    sanitized_cmdline=(${CMDLINEARGS[@]})
}

function add_aboot_param()
{
    # shellcheck disable=SC2178
    CMDLINEARGS="$1"
    current_aboot_cmdline=$(cat /proc/cmdline)
    remove_default_args "${current_aboot_cmdline[@]}"
    sanitized_cmdline+=(${CMDLINEARGS[@]})

    # want to keep spaces as delimiter
    # shellcheck disable=SC2124
    new_aboot_cmdline="${sanitized_cmdline[@]}"
    aboot-update -c "${new_aboot_cmdline}" "$(uname -r)" || exit 1
    dd if=/boot/aboot-"$(uname -r)".img of=/dev/disk/by-partlabel/boot_a || exit 1
    sync
}

function remove_aboot_param()
{
    # shellcheck disable=SC2178
    CMDLINEARGS="$1"
    current_aboot_cmdline=$(cat /proc/cmdline)
    remove_default_args "${current_aboot_cmdline[@]}"
    remove_from_cmdline=(${CMDLINEARGS[@]##-})
    if [ -z "${sanitized_cmdline[0]}" ]; then
        echo "WARNING: Unable to find parameter in the allowed list."
        exit 0
    else
        for i in "${!sanitized_cmdline[@]}"; do
            for j in "${!remove_from_cmdline[@]}";do
                if [[ "${remove_from_cmdline[${j}]}" =~ "=" ]]; then # remove the exact param and value pair
                    if echo "${remove_from_cmdline[${j}]}" | grep -q "${sanitized_cmdline[${i}]}"; then
                        # shellcheck disable=SC2184
                        unset "sanitized_cmdline[${i}]"
                    fi
                else
                    if [[ "${remove_from_cmdline[${j}]}" == "${sanitized_cmdline[${i}]/=*}" ]]; then # remove all occurences of param.
                        # shellcheck disable=SC2184
                        unset "sanitized_cmdline[${i}]"
                    fi
                fi
            done
        done
        # want to keep spaces as delimiter
        # shellcheck disable=SC2124
        new_aboot_cmdline="${sanitized_cmdline[@]}"
        aboot-update -c "${new_aboot_cmdline}" "$(uname -r)" || exit 1
        dd if=/boot/aboot-"$(uname -r)".img of=/dev/disk/by-partlabel/boot_a || exit 1
        sync
    fi
}
function change_cmdline()
{
    # shellcheck disable=SC2178
    CMDLINEARGS="$1"
    echo "Old cmdline:"
    cat /proc/cmdline

    # Update the boot loader.
    default=$(/sbin/grubby --default-kernel)

    # If the first character is - in the arguments, we remove them from
    # the kernel commandline.
    if echo "${CMDLINEARGS[@]}" | grep -q "^-"; then
        echo "Cmdline to be removed: ${CMDLINEARGS##-}"
        if cki_is_abd; then
            remove_aboot_param "${CMDLINEARGS[@]}"
        elif [ -e /run/ostree-booted ]; then
            rpm-ostree kargs --delete-if-present="${CMDLINEARGS##-}" --import-proc-cmdline
        else
            /sbin/grubby --remove-args="${CMDLINEARGS##-}" --update-kernel="${default}"
        fi
    else
        # shellcheck disable=SC2128
        echo "Cmdline to be added: ${CMDLINEARGS}"
        if cki_is_abd; then
            add_aboot_param "${CMDLINEARGS[@]}"
        elif [ -e /run/ostree-booted ]; then
            rpm-ostree kargs --append-if-missing="${CMDLINEARGS##-}" --import-proc-cmdline
        else
            # shellcheck disable=SC2128
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
    # shellcheck disable=SC2178
    CMDLINEARGS="$1"
    echo "New cmdline:"
    cat /proc/cmdline

    if echo "${CMDLINEARGS[@]}" | grep -q "^-"; then
        ! grep -q "${CMDLINEARGS[@]##-}" /proc/cmdline && return 0
    else
        grep -q "${CMDLINEARGS[@]}" /proc/cmdline && return 0
    fi

    return 1
}
function change_and_verify(){
    if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then
        # Prepare for the first reboot.
        change_cmdline "${CMDLINEARGS[@]}"
        rstrnt-reboot
    else
        # The reboot has finished. Verify the cmdline.
        verify_cmdline "${CMDLINEARGS[@]}"
    fi
}
