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

K_AUTO_CHECK=${K_AUTO_CHECK:-false}

SetupKdump()
{
    if [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then

        GetHWInfo
        [[ "${K_ARCH}" =~ i.86|x86_64 ]] && GetBiosInfo

        # Kexec-tools is not installed by default on Fedora
        $IS_FC && PrepareKdump

        # In ia64 arch, the path of vmlinuz is /boot/efi/efi/redhat, it different with other arch.
        [[ "${K_ARCH}"  = "ia64" ]] && {
            /sbin/grubby --set-default="/boot/efi/efi/redhat/vmlinuz-$(uname -r)"
        }

        # For uncompressed kernel, i.e. vmlinux
        [[ "${VMLINUZ_PATH}" == *vmlinux* ]] && {
            Log "Modifying ${KDUMP_SYS_CONFIG} properly for 'vmlinux'."
            sed -i 's/\(KDUMP_IMG\)=.*/\1="vmlinux"/' ${KDUMP_SYS_CONFIG}
        }

        # For kernel-rt
        $IS_RT && [ -f /usr/bin/rt-setup-kdump ] && {
            Log "Modifying ${KDUMP_SYS_CONFIG} properly for RT."
            set -x; /usr/bin/rt-setup-kdump -g; set +x
        }

        # RHEL5 ppc64 kdump need kernel-kdump
        $IS_RHEL5 && [ "${K_ARCH}" = "ppc64" ] && {
            InstallKernel "kernel-kdump-${K_VER}-${K_REL}.${K_ARCH}" ||
            FatalError "Failed installing kernel-kdump!"
        }

        # If testing crash tool, then kernel-debuginfo needed
        [ "${NODEBUGINFO}" = "false" ] && InstallDebuginfo

        # When ${K_AUTO_CHECK} is true, check if auto crash memory reservation works.
        # Report errors and continue test if it failed to reserve memory automatically.
        if [ "${K_AUTO_CHECK}" = "true" ] && ! $IS_FC; then
            CheckAutoReservation || Error "Crash memory auto reservation check failed"
        fi

        # Ensure Kdump Kernel memory reservation
        # KARGS="" | "<non-fadump-opts>"": no reset-
        #   e.g.: KARGS="amd_iommu=off"
        # KARGS="fadump=xxx"             : do reset-
        local reboot_required=false
        grep -q 'crashkernel' <<< "${KER1ARGS}" || {
            local kdumpMem
            local fadump_opts
            fadump_opts=$(grep -oE "fadump=\w+" <<< "${KER1ARGS}")
            if kdumpctl -h 2>&1 | grep -q reset-crashkernel && \
                    [ -n "${fadump_opts}" ]; then
                fadump_opts="--${fadump_opts}"
                LogRun "kdumpctl reset-crashkernel ${fadump_opts}"
                reboot_required=true
            else # use default value from kdump.sh
                kdumpMem="$(DefKdumpMem)"
            fi
            [ -z "${KER1ARGS}" ] || kdumpMem=" ${kdumpMem}"

            if $IS_RHEL5 ; then
                KER1ARGS+="${kdumpMem}"
            elif [ "$(cat /sys/kernel/kexec_crash_size)" -eq 0 ] ; then # for fedora
                # Check kdump status if it's fadump mode which caused kexec_crash_size is 0
                kdumpctl status > /dev/null 2>&1 || {
                    if kdumpctl -h 2>&1 | grep -q reset-crashkernel && [ "${#kdumpMem}" -gt 1 ]; then
                        LogRun "kdumpctl reset-crashkernel"
                        reboot_required=true
                    else
                        KER1ARGS+="${kdumpMem}"
                    fi
                }
            fi
        }

        if [ -n "${KER1ARGS}" ]; then
            # Support translating crashkernel=auto test request to crashkernel=XXM for rhel9+
            if grep -q crashkernel=auto <<< "${KER1ARGS}" || \
                    kdumpctl -h 2>&1 | grep -q reset-crashkernel; then
                KER1ARGS=${KER1ARGS/crashkernel=auto/$(DefKdumpMem)}
            fi

            # touch "${K_REBOOT}"

            # Kdump service will not be enabled if crashkernel=auto && system
            # memory is less the threshold required by kdump service.
            Log "Preparing to update kernel options: ${KER1ARGS}"
            Log "Enable kdump service"
            /bin/systemctl enable kdump.service || /sbin/chkconfig kdump on

            Log "Changing boot loader."

            UpdateKernelOptions "${KER1ARGS}" || FatalError "Error changing boot loader."
            reboot_required=true
        fi

        if $reboot_required; then
            Report 'pre-reboot'
            sync
            RhtsReboot
        fi
    fi

    # Make sure kdumpctl is operational
    # If kdump service is not started yet, wait for max 3 mins.
    # It may take time to start kdump service.
    Log "Checking kdump service status"
    local retval=0
    for i in {1..5}
    do
        CheckKdumpStatus
        retval=$?
        [ "${retval}" -eq 0 ] && break
        sleep 60
    done
    # show kexec-tools & crash version after pkginstall
    LogRun "rpm -q kexec-tools crash ${K_NAME/-core}"
    LogRun "uname -r"
    LogRun "cat /proc/cmdline"
    Log "Total system memory: $(lshw -short | grep -i "System Memory" | awk '{print $3}')"
    LogRun "kdumpctl showmem || cat /sys/kernel/kexec_crash_size"
    grep "fadump=on" /proc/cmdline > /dev/null && {
        Log "Dump mode is fadump"
        dmesg | grep "firmware-assisted dump" | grep -i "Reserved"
    }

    # [ -f "${K_REBOOT}" ] && rm -f "${K_REBOOT}"

    local msg_log=${K_TESTAREA}/kdump.messages.log
    if [ "${retval}" -ne 0 ]; then
        journalctl -b > "${msg_log}"
        # Bug 1754815 Kdump: Building kdump initramfs img may fail with
        # 'Write failed because Bad file descriptor' occasionally
        # Try one more time.
        if grep -qi "failed to make kdump initrd" "${msg_log}" && \
           grep -qi "Write failed because Bad file descriptor" "${msg_log}" ; then

            Warn "Kdump failed to make kdump initrd: Write failed because Bad file descriptor (BZ#1754815)."
            Log "Try restarting kdump service one more time"
            systemctl restart kdump 2>&1
            systemctl status kdump --no-pager 2>&1
            retval=$?
        fi
    fi

    # Upload kdump journal log
    if which journalctl > /dev/null 2>&1 ; then
        journalctl -u kdump > "${msg_log}"
        grep -iq "No entries" "${msg_log}"  && \
            journalctl -b > "${msg_log}"
        RhtsSubmit "${msg_log}"
    else
        RhtsSubmit /var/log/messages
    fi

    if [ "${retval}" -ne 0 ]; then
        sync;sync;sync;
        MajorError "Kdump is not operational!"
    else
        # Submit kdump rd img for later debugging if fails.
        ${NOKDUMPRD} || ReportKdumprd
    fi
}

#--- Start ---

Multihost 'SetupKdump'
