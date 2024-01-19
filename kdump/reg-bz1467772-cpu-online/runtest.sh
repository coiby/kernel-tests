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

# Bug 1467772 - The kdump initrd rebuild happens frequently while acpi_cpufreq kernel module is loaded
# Fixed in RHEL-6.10 kexec-tools-2.0.0-308.el6
CheckSkipTest kexec-tools 2.0.0-308 && Report

# Get CPU number
cpu_num=$(lscpu | grep -i on-line | awk -F'[ ,-]' '{print $NF}')
CPUOL_INTERVAL=${CPUOL_INTERVAL:-5}

RegressionTest() {

    # Get a CPU number
    [ "$cpu_num" -lt 1 ] && {
        Warn "This machine has only 1 CPU which cannot be used for online/offline CPU test"
        Report
        return
    }

    # Offline a CPU
    Log "Take CPU ${cpu_num} offline"
    LogRun "echo 0 >/sys/devices/system/cpu/cpu${cpu_num}/online"
    [ "$(cat /sys/devices/system/cpu/cpu${cpu_num}/online)" != "0" ] && {
        # shellcheck disable=SC2154
        report_result "Failed to offline cpu" "FAIL" "${error}"
        Error "Failed to offline cpu${cpu_num}"
    }

    # Restart kdump service
    RestartKdump

    # Bring the CPU online
    Log "Take CPU ${cpu_num} back to online"
    LogRun "echo 1 >/sys/devices/system/cpu/cpu${cpu_num}/online"
    [ "$(cat /sys/devices/system/cpu/cpu${cpu_num}/online)" != "1" ] && {
        report_result "Failed to online cpu" "FAIL" "${error}"
        Error "Failed to online cpu${cpu_num}"
    }

    LogRun "sleep ${CPUOL_INTERVAL}"
    # Make sure kdumpctl is operational
    # If kdump service is not started yet, wait for max 5 mins.
    # It may take time to start kdump service.
    Log "Checking kdump service status"
    for i in $(seq 5)
    do
        CheckKdumpStatus && break
        sleep 60
    done

    if which journalctl >/dev/null 2>&1; then
        journalctl -u kdump -b >kdump_journalctl.log
        Log "Checking kexec: load/unload kdump kernel logs"
        if grep "kexec: unloaded kdump kernel" kdump_journalctl.log; then
            report_result "The kdump service is repeatedly restarted" "FAIL" "${error}"
            MajorError "The kdump service is repeatedly restarted"
        fi
        RhtsSubmit "$(pwd)/kdump_journalctl.log"
        rm kdump_journalctl.log
        sync
    else
        RhtsSubmit "/var/log/messages"
        sync
    fi
}

CPUBroughBackPanic() {
    Log "Will take panic on CPU ${cpu_num}"
    LogRun "cat /proc/sys/kernel/sysrq"
    taskset -c "${cpu_num}" sh -c "echo c >/proc/sysrq-trigger"
}

# --- start ---
Multihost SystemCrashTest CPUBroughBackPanic RegressionTest
