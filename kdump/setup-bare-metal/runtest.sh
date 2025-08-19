#!/bin/sh
# shellcheck disable=SC3010
# shellcheck disable=SC3011
# shellcheck disable=SC3060
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
K_FORCE_RESET_CK=${K_FORCE_RESET_CK:-false}

SetupKdump()
{
    if [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then

        GetHWInfo
        [[ "${K_ARCH}" =~ i.86|x86_64 ]] && GetBiosInfo

        # Check if kexec-tools or kdump-utils is installed by default
        # Since RHEL-10,kdump-utils is the kdump main package.
        if $IS_RHEL; then
            rpm -q --quiet ${MAIN_RPM_PACKAGE} || FatalError "Did not install the kdump main package ${MAIN_RPM_PACKAGE} by default!"
        fi

        # kdump main package is not installed by default on Fedora
        $IS_FC && PrepareKdump

        # In ia64 arch, the path of vmlinuz is /boot/efi/efi/redhat, it different with other arch.
        [[ "${K_ARCH}"  = "ia64" ]] && {
            /sbin/grubby --set-default="/boot/efi/efi/redhat/vmlinuz-$(uname -r)"
        }

        # For uncompressed kernel, i.e. vmlinux
        [[ "${VMLINUZ_PATH}" == *vmlinux* ]] && {
            Log "Modifying ${KDUMP_SYS_CONFIG} properly for 'vmlinux'."
            sed -i 's/\(KDUMP_IMG\)=.*/\1="vmlinux"/' "${KDUMP_SYS_CONFIG}"
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
        _reboot_required=false
        _fadump_opts=$(grep -oE "fadump=\w+" <<< "${KER1ARGS}")

        # if ${KER1ARGS} has no 'crashkernel=xxx'(could be empty):
        # fadump:
        # (0). ResetCrashkernel fadump=xxx
        # legacy/specific cases:
        # (1). RHEL-5 or the memory below the threshold - get the crashkernel value from function DefKdumpMem()
        # (2). Fedora system - get the crashkernel value from function ResetCrashkernel()
        # (3). RHEL-8,this is a known bug2111855 that on some aarch64 machines,need to reserve more memory for kdump test.
        #      for example:ampere-mtsnow-altra%,ampere-mtjade-altra% and arm-kernel%,the model name is Neoverse-N1.
        #      set the crashkernel=768M to ovoid OOM issue.
        # (4). Automotive system - gets the crashkernel value from function ResetCrashkernel()
        grep -q 'crashkernel' <<< "${KER1ARGS}" || { # do some default set on "crashkernel"
            # - fadump mode;
            # - legacy cases: RHEL5 or if the memory below the threshold or fedora:non-fadump
            if [ -n "${_fadump_opts}" ] || $IS_RHEL5 || ! IfMemoryAboveThreshold; then
                ResetCrashkernel "${_fadump_opts}"
            elif [ "$(cat /sys/kernel/kexec_crash_size)" -eq 0 ]; then
                # for fedora:non-fadump
                kdumpctl status > /dev/null 2>&1 || {
                    ! $IS_FC && ! eval cki_is_kernel_automotive && FatalError "Kdump is not operational.please check the system."
                    ResetCrashkernel
                }
            elif $IS_RHEL8 && [ "${K_ARCH}" = "aarch64" ] && grep -q "crashkernel=auto" /proc/cmdline; then
                [ "$(lscpu |grep '^Model name:'| awk '{print $NF}')" = "Neoverse-N1" ] && KER1ARGS="${KER1ARGS} crashkernel=768M"
            fi
        }

        if [ -n "${KER1ARGS}" ]; then
            Log "Preparing to update kernel options: ${KER1ARGS}"
            Log "Enable kdump service"
            /bin/systemctl enable kdump.service || /sbin/chkconfig kdump on

            Log "Changing boot loader."

            UpdateKernelOptions "${KER1ARGS}" || FatalError "Error changing boot loader."
            _reboot_required=true
        fi

        # if K_FORCE_RESET_CK is true,force the crashkernel value to the default value.
        # K_FORCE_RESET_CK has higher priority than KER1ARGS(if it has crashkernel=xxxM)
        # - Trigger reset-crashkernel (when it supports 'kdumpctl reset-crashkernel')
        # - Reset crashkernel=auto in /proc/cmdline (when it supports crashkernel=auto,like rhel-7 and rhel-8)
        # - Get the default value from DefKdumpMem()(when it did not support crashkernel=auto or 'kdumpctl reset-crashkernel',like rhel-5)
        if [ "${K_FORCE_RESET_CK}" = "true" ]; then
            ResetCrashkernel "${_fadump_opts}"
        fi

        if ${_reboot_required}; then
            Report 'pre-reboot'
            sync
            RhtsReboot
        fi
    fi

    # Needed for automotive SOC devices that dont come with kexec-tools pre installed and kdump systemd for startup.
    if cki_is_kernel_automotive; then
        kdumpctl status > /dev/null 2>&1 || LogRun "kdumpctl start"
    fi
    # Make sure kdumpctl is operational
    # If kdump service is not started yet, wait for max 3 mins.
    # It may take time to start kdump service.
    Log "Checking kdump service status"
    # shellcheck disable=SC3043
    local retval=0
    # shellcheck disable=SC2034
    # shellcheck disable=SC3009
    for i in {1..5}
    do
        CheckKdumpStatus
        retval=$?
        [ "${retval}" -eq 0 ] && break
        sleep 60
    done
    # Show kernel,kexec-tools,kdump-utils,crash version after pkginstall
    # Since RHEL-10,kexec-tools is split into kexec-tools,kdump-utils and makedumpfile.
    # kdump-utils depends on kexec-tools and makedumpfile.
    LogRun "rpm -q kexec-tools kdump-utils makedumpfile crash ${K_NAME/-core}"
    LogRun "uname -r"
    LogRun "cat /proc/cmdline"
    ## Log "Total system memory: $(lshw -short | grep -i "System Memory" | awk '{print $3}')"
    Log "Total system memory: $(lsmem | grep -i "Total online memory:" | awk '{print $4}')"
    LogRun "kdumpctl showmem || cat /sys/kernel/kexec_crash_size"
    grep -oE "fadump=\w+" /proc/cmdline > /dev/null && {
        Log "Dump mode is fadump"
        dmesg | grep "firmware-assisted dump" | grep -i "Reserved"
    }

    # [ -f "${K_REBOOT}" ] && rm -f "${K_REBOOT}"

    # shellcheck disable=SC3043
    local msg_log="${K_TESTAREA}"/kdump.messages.log
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
