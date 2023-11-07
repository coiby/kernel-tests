#!/bin/sh
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
. ../include/runtest.sh

# Specify which kernel will be switched to. By default, it will be switch to current kernel version.
KEXEC_VER=${KEXEC_VER:-"$(uname -r)"}

# Allow passing extra kexec options for debugging. e.g. -d
EXTRA_KEXEC_OPTIONS=${EXTRA_KEXEC_OPTIONS:-""}

# Whether passing -s to kexec options
# If false, it will append -s to kexec options if SecureBootEnforced is detected.
# If true, it will append -s to kexec options anyway.
USE_FILE_BASED_SYSCALL=${USE_FILE_BASED_SYSCALL:-"false"}

# Allow specifying kernel boot cmdline for kexec kernel.
# You may either provide a complete KEXEC_BOOT_CMDLINE, or a KEXEC_BOOT_CMDLINE_APPEND
# which will be appeneded to current cmdline options.
# If both are provided, KEXEC_BOOT_CMDLINE + KEXEC_BOOT_CMDLINE_APPEND will be used.
KEXEC_BOOT_CMDLINE=${KEXEC_BOOT_CMDLINE:-"$(cat /proc/cmdline)"}
KEXEC_BOOT_CMDLINE_APPEND=${KEXEC_BOOT_CMDLINE_APPEND:-""}

# The command run after kexec load, by default it's a system reboot.
KEXEC_BOOT_AFTER_CMD=${KEXEC_BOOT_AFTER_CMD:-"SimpleReboot"}

CheckSecureBoot() {
    Log "Checking if secure boot is enabled"
    if [ "$(isSecureBootEnforced)" = "0" ]; then
        Log "Secure Boot is enabled."
        return 0
    elif [ -f /sys/kernel/security/securelevel ]; then
        local securelevel="(cat /sys/kernel/security/securelevel)"
        [ "$securelevel" = "1" ] && {
            Log "/sys/kernel/security/securelevel is set to 1 (Secure Mode). "
            return 0
        }
    fi

    # check again with mokutil
    rpm -q mokutil || InstallPackages mokutil
    mokutil --sb-state | grep -i 'SecureBoot enabled' && return 0

    Log "Secure boot is not enabled"
    return 1
}


KexecBoot() {
    DisableAVCCheck

    local _initrd_img_path _vmlinuz_path
    if system_ostree; then
        # kernel-automotive kernel and initramfs img on ostree contains a hash:
        # kernel image - vmlinuz-$(uname -r)-${commit_hash}
        # initramfs image - initramfs-$(uname -r).img-${commit_hash}
        _initrd_img_path=$(find $K_BOOT -name "${INITRD_PREFIX}-${KEXEC_VER}.img-*")
        _vmlinuz_path=$(ls ${K_BOOT}/vmlinuz-${KEXEC_VER}!(*debug*|*64k*|*rt*))
        [ -z "${_vmlinuz_path}" ] && _vmlinuz_path=$(ls ${K_BOOT}/vmlinux-${KEXEC_VER}!(*debug*|*64k*|*rt*))
    else
        _initrd_img_path="$K_BOOT/$INITRD_PREFIX-${KEXEC_VER}.img"
        _vmlinuz_path="${K_BOOT}/vmlinuz-${KEXEC_VER}"
        [ -z "${_vmlinuz_path}" ] && _vmlinuz_path="${K_BOOT}/vmlinux-${KEXEC_VER}"
    fi

    # 'kexec -l' or 'kexec -c' can only be run on a system supporting PSCI
    # Warn and stop the test if it doesn't support PSCI
    # https://bugzilla.redhat.com/show_bug.cgi?id=1528933#c2
    if [ "$K_ARCH" = "aarch64" ]; then
        local supported=1
        if which journalctl 2> /dev/null; then
            journalctl -k | grep -i psci | grep -i "is not implemented" && supported=0
        else
            grep -i psci /var/log/messages | grep -i "is not implemented" && supported=0
        fi

        if [ "$supported" -eq 0 ]; then
            Warn "This aarch64 system doesn't support PSCI. Terminate the test."
            return
        fi
    fi

    if [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then
        #PrepareReboot
        # create $K_REBOOT only if a reboot will be performed after kexec load action.
        # if [[ ${KEXEC_BOOT_AFTER_CMD} == *reboot* ]] || \
        #    [[ ${KEXEC_BOOT_AFTER_CMD} == *RhtsReboot* ]] || \
        #    [[ ${KEXEC_BOOT_AFTER_CMD} == *" -e"* ]]; then
        #     touch "${K_REBOOT}"
        # fi
        local cmd="kexec ${EXTRA_KEXEC_OPTIONS} -l"

        # KEXEC options
        # if "EXTRA_KEXEC_OPTIONS" specifies '-s', then there is no need to
        # check if the machine is secure boot enabled or if "USE_FILE_BASED_SYSCALL"
        # is specified.
        if ! grep "\-s " <<< "${EXTRA_KEXEC_OPTIONS}" && ! grep "\-s$" <<< "${EXTRA_KEXEC_OPTIONS}"; then
            if [ "${USE_FILE_BASED_SYSCALL}" = "true" ]; then
                cmd="${cmd} -s"
            else
                CheckSecureBoot && cmd="${cmd} -s"
            fi
        fi

        # Kernel boot options
        local boot_cmdline
        boot_cmdline="${KEXEC_BOOT_CMDLINE}"
        if [ -n "${KEXEC_BOOT_CMDLINE_APPEND}" ]; then
             boot_cmdline+=" ${KEXEC_BOOT_CMDLINE_APPEND}"
        fi

        # print cert loading status in case of -s
        if [[ "$cmd " =~ "-s " ]]; then
            Log "Check journalctl log for cert loaded"
            if which journalctl ; then
                journalctl -lk --boot 0 | grep -i Loaded | grep cert
            else
                grep -i Loaded /var/log/messages | grep cert
            fi

            which pesign 2> /dev/null || InstallPackages pesign
            LogRun "pesign -v -S --in ${_vmlinuz_path}"
        fi

        # Make sure kdump service is done running 'kexec -p' load
        # So kexec -l won't competing resources with kexec -p
        # bz1769618: kexec_load failed: Device or resource busy
        if which kdumpctl &> /dev/null; then
            kdumpctl status
        else
            service kdump status --no-pager
        fi

        # Prepare kexec cmd and run kexec
        LogRun "${cmd} ${_vmlinuz_path} --initrd=${_initrd_img_path} --command-line=\"${boot_cmdline}\""
        if [ "$?" -ne 0 ] || [ "$(cat /sys/kernel/kexec_loaded)" = "0" ]; then
            # rm -f "${K_REBOOT}"
            Error "Loading kexec kernel ${KEXEC_VER} failed."
            LogRun "cat /sys/kernel/kexec_loaded"
            return
        fi

        # Run KEXEC_BOOT_AFTER_CMD
        LogRun "${KEXEC_BOOT_AFTER_CMD}" || Error "Failed to execute command: $KEXEC_BOOT_AFTER_CMD"

    elif [ "${RSTRNT_REBOOTCOUNT}" -eq 1 ]; then
        # rm -f "${K_REBOOT}"

        Log "Kexec'd to kernel $(uname -r)"
        Report 'boot-kexec-kernel'

        # Validate if this is the kernel loaded before rebooting.
        local test_pass=true
        LogRun "uname -r"
        LogRun "cat /proc/cmdline"

        if [ -n "${KEXEC_BOOT_CMDLINE_APPEND}" ]; then
            grep -q "${KEXEC_BOOT_CMDLINE_APPEND}" < /proc/cmdline || test_pass=false
        else
            grep -q "${KEXEC_BOOT_CMDLINE}" < /proc/cmdline || test_pass=false
        fi

        if [ "$(uname -r)" != "$KEXEC_VER" ]; then
            test_pass=false
        fi

        if [ "$test_pass" = "true" ]; then
            Log "Kexec boot to kernel $KEXEC_VER successfully."
        else
            Error "Kexec boot failed. Either kernel version or boot options is not as expected"
        fi
    else
        Error "Detecte unexpected reboot. Please check test and console log."
    fi
}

# --- start ---
Multihost "KexecBoot"
