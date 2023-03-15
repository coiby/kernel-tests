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

# Applicable to ppc64le PowerVM only
# Bug 1549355 - kdump fails when crash is triggered after cpu add operation
# Fixed in RHEL-7.7 kexec-tools-2.0.15-29
if [ "${K_ARCH}" != ppc64le ]; then
    Skip "Test is applicable to ppc64le only"
    Report
fi
CheckSkipTest kexec-tools 2.0.15-29 && Report

CPURemoveAdd() {
    which drmgr >/dev/null 2>&1 || InstallPackages powerpc-utils

    # Print out cpuinfo
    LogRun "Check CPU info"
    LogRun "lscpu"

    # Checking Sockets number and skip
    socket_num=$(lscpu | grep Socket | awk '{print $NF}')
    if [ "${socket_num}" -lt 2 ]; then
        Warn "Test requires two cpu sockets machine to run"
        Report
    fi

    # Remove one CPU
    Log "Remove one CPU socket"
    LogRun "drmgr -c cpu -r -q 1" || MajorError "Failed to remove cpu by cmd drmgr"
    LogRun "lscpu"

    cpu_num=$(lscpu | grep ^CPU | awk '{print $2}')

    # Restart kdump service
    RestartKdump

    # Add the CPU back
    Log "Add CPU socket back"
    LogRun "drmgr -c cpu -a -q 1"
    LogRun "lscpu"

    # expect kdumpctl would be reloaded after cpu is added back.
    LogRun "kdumpctl status"
}

PanicOnCPU() {
    # Trigger panic on the newly added cpu
    Log "Will take panic on CPU ${cpu_num}"
    LogRun "cat /proc/sys/kernel/sysrq"
    sync
    sleep 15 # wait 15 seconds for log records
    taskset -c "${cpu_num}" sh -c "echo c >/proc/sysrq-trigger"
}

# --- start ---
Multihost SystemCrashTest PanicOnCPU CPURemoveAdd
