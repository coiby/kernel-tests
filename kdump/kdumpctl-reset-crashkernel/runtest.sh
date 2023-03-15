#!/bin/sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/kdump/kdumpctl-reset-crashkernel
#   Description: Test availability for kdumpctl reset-crashkernel
#   Author: Ruowen Qin <ruqin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat
#
#   SPDX-License-Identifier: GPL-2.0-or-later WITH GPL-CC-1.0
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Include Beaker environment...

. ../include/runtest.sh

CheckSkipTest kexec-tools 2.0.22-9 && Report

CheckKdumpctlOption() {
    kdumpctl 2>&1 | grep -q $1
    return $?
}

ResetCrashkernel() {
    CheckKdumpctlOption 'reset-crashkernel' || {
        MajorError "no kdumpctl option reset-crashkernel"
    }

    Log "Current REBOOTCOUNT: $RSTRNT_REBOOTCOUNT"

    # check the crashkernel_default file exist
    crashkernel_default=$(GetCrashkernelDefault)
    if [[ $? -ne 0 || -z "$crashkernel_default" ]]; then
        MajorError "GetCrashkernelDefault function in /kdump/include/lib failed, no crashkernel_default value found"
    fi

    if [[ -z "${RSTRNT_REBOOTCOUNT}" ]]; then
        MajorError "No parameter RSTRNT_REBOOTCOUNT"
    fi

    if [[ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]]; then
        # Prepare for the first reboot.

        # update crashkernel size to 256M
        UpdateKernelOptions "crashkernel=256M" || MajorError "Error changing boot loader."

        Report 'Pre-reboot modify crashkernel=256M'
        sync
        RhtsReboot

    elif [[ "${RSTRNT_REBOOTCOUNT}" -eq 1 ]]; then

        # check crashkernel size to 256M
        if ! grep -q "crashkernel=256M" /proc/cmdline; then
            Error "crashkernel=256M didn't present in kernel cmdline"
            LogRun "cat /proc/cmdline"
        fi

        # reset kdump crashkernel to default size
        kdumpctl reset-crashkernel

        Report 'Pre-reboot reset crashkernel'
        sync
        RhtsReboot

    elif [[ "${RSTRNT_REBOOTCOUNT}" -eq 2 ]]; then

        # check reset-crashkernel to default value
        if ! grep -q "${crashkernel_default}" /proc/cmdline; then
            Error "Reset-crashkernel failed, default $crashkernel_default didn't present in kernel cmdline"
            LogRun "cat /proc/cmdline"
        fi
    fi

}

# --- start ---
Multihost ResetCrashkernel
