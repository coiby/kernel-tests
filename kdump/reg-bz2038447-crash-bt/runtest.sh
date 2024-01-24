#!/bin/bash
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

# Bz2038447 -  crash segfault with "bt -a" on aarch64 even with latest upstream
# Fixed in RHEL-8.6 crash-7.3.1-5.el8.
if [ "${K_ARCH}" == "aarch64" ];then
    CheckSkipTest crash 7.3.1-5.el8 && Report
fi

OfflineCPU(){

    # online CPU number
    local cpu_online=0
    cpu_online=$(lscpu | grep -i on-line | awk -F '[ ,-]' '{print $NF}')

    [ "$cpu_online" -lt 1 ] && {
        Warn "This machine has only 1 CPU which cannot be used for offline CPU test"
        Report
        return
    }

    # offline cpu
    local cpu_offline=$(((cpu_online+1)/2))
    local offline_num=0

    for ((i=1; i<cpu_offline+1; i++ ))
    do
      LogRun "echo 0 > /sys/devices/system/cpu/cpu$i/online"
      [ "$(cat /sys/devices/system/cpu/cpu"$i"/online)" == "0" ] && {
          offline_num=$((offline_num+1))
      }
    done

    [ $offline_num -eq 0 ] && {
        Error "Failed to offline cpu."

    }

}

AnalyseCrashBt()
{
    # Only check the return code of this session.
    cat <<EOF > "${K_TESTAREA}/crash-simple.cmd"
bt -a
exit
EOF

    PrepareCrash

    CheckVmlinux
    GetCorePath

    [ -f "${K_TESTAREA}/crash-simple.vmcore.log" ] && rm -f "${K_TESTAREA}/crash-simple.vmcore.log"
    # shellcheck disable=SC2154
    CrashCommand "" "${vmlinux}" "${vmcore}" "crash-simple.cmd"
    rm -f "${K_TESTAREA}/crash-simple.cmd"
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC OfflineCPU AnalyseCrashBt

