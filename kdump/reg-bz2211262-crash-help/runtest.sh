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

# Bz2211262 - [FJ8.8 Bug]: crash utility results in segmentation fault when non-panicking CPUs fail to get stopped at panic
# Fixed in RHEL-8.9 crash-7.3.2-8.el8.

PrepareCrash

if $IS_RHEL8 && [ "$(uname -m)" = "aarch64" ]; then
    CheckSkipTest crash 7.3.2-8 && Report
elif $IS_RHEL9 && [ "$(uname -m)" = "aarch64" ]; then
    Warn "This issue will be fixed on RHEL-9.4,tracked by RHEL-10534."
else
    Skip "Currently,only aarch64 has no NMI."
    Report
fi


TriggerPanicAndAnalyse()
{
    local cpu_online=0
    cpu_online=$(lscpu | grep -i on-line | awk -F '[ ,-]' '{print $NF}')

    [ "$cpu_online" -lt 3 ] && {
        Warn "This machine has $cpu_online CPUs,it need at least 4 CPUs."
        Report
        return
    }

    if [ ! -f "${K_REBOOT}" ]; then
        Log "Prepare reboot"
        PrepareReboot

        Log "Check kdump status before triggering panic"
        CheckKdumpStatus

        Log "Build the module that used to trigger panic"
        MakeModule 'repro'

        touch "${K_REBOOT}"; sync; sync; sync;
        Log "Trigger Panic"
        LogRun "echo 0 > /sys/devices/system/cpu/cpu1/online"
        LogRun "insmod repro/repro.ko"

        sleep 60
        Error "Failed to trigger system panic"
        rm -f "${K_REBOOT}"
    else
        rm -f "${K_REBOOT}"
        cat <<EOF > "crash-test.cmd"
help -D
bt -c 2
exit
EOF
        RhtsSubmit "crash-test.cmd"
        CheckVmlinux
        GetCorePath

        crash -i "crash-test.cmd" "${vmlinux}" "${vmcore}" > "crash-test.vmcore.log"
        RhtsSubmit "crash-test.vmcore.log"

        notes1="$(grep 'notes\[1\]: 0 '  "crash-test.vmcore.log" | awk '{print $NF}')"
        notes2="$(grep 'notes\[2\]: 0 '  "crash-test.vmcore.log" | awk '{print $NF}')"

        # Check if the mapping between NT_PRSTATUS notes and cpu numbers is correct
        # The expected result is that CPU#1 and CPU#2 don't have NT_PRSTATUS notes:
        # crash> help -D
        # .....
        #     notes[1]: 0
        #     notes[2]: 0
        # .....
        # crash>
        if [ "$notes1" != "$notes2" ] || [ -z "$notes2" ]; then
            Error "Mapping between NT_PRSTATUS notes and cpu numbers is not correct,please check crash-test.vmcore.log."
        fi

        # Below warning info is expected,so delete them that avoid them as error messages:
        # WARNING: cpu 2: invalid NT_PRSTATUS note (n_type != NT_PRSTATUS)
        # WARNING: cpu 1: cannot find NT_PRSTATUS note
        # WARNING: cpu 2: cannot find NT_PRSTATUS note
        # WARNING: cannot determine starting stack frame for task xxxxxx
        sed -i '/WARNING: cpu 2: invalid NT_PRSTATUS note\|cannot find NT_PRSTATUS note\|WARNING: cannot determine starting stack frame for task/d' "crash-test.vmcore.log"

        ValidateCrashOutput "crash-test.vmcore.log"

        rm -f "crash-test.vmcore.log"
        rm -f "crash-test.cmd"

    fi

}

#+---------------------------+

Multihost TriggerPanicAndAnalyse
