#!/bin/sh

# Copyright (c) 2018 Red Hat, Inc. All rights reserved.
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

#  Author: Xiaowu Wu    <xiawu@redhat.com>
#  Update: Ruowen Qin   <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1521003 - kdump kernel in a KVM virtual machine hangs sporadically
#               at an early stage during startup
# Fixed in RHEL-7.6 kernel-3.10.0-863.el7
CheckSkipTest kernel 3.10.0-863 && Report

ConfigCmdline() {

    if [ ! -f "${K_REBOOT}_config" ]; then
        touch "${K_REBOOT}_config"

        Log "Prepare Kdump with notsc enabled on kernel options"
        UpdateKernelOptions "notsc" || MajorError "Failed to add notsc to kernel options"
        RhtsReboot
    else
        rm "${K_REBOOT}_config"

        if ! grep -q notsc /proc/cmdline; then
            LogRun "cat /proc/cmdline"
            MajorError "notsc doesn't present in  kernel options."
        fi

        Log "Remove notsc if it's in KDUMP_COMMANDLINE_REMOVE in kdump sysconfig"
        AppendSysconfig KDUMP_COMMANDLINE_REMOVE remove notsc
        RestartKdump
    fi

}


ValidateCmdline() {

    if [ ! -f "${K_REBOOT}_validate" ]; then
        touch "${K_REBOOT}_validate"

        Log "Test cleanup: Remove notsc from kernel options"
        UpdateKernelOptions "-notsc"
        RhtsReboot
    else
        rm "${K_REBOOT}_validate"

        if grep -q notsc /proc/cmdline; then
            LogRun "cat /proc/cmdline"
            Error "notsc is not deleted from kernel options as expected."
        fi
    fi
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC ConfigCmdline ValidateCmdline
