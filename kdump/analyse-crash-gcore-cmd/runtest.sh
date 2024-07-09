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

CheckUnexpectedReboot

# crash-gcore-cmd doesn't support s390x on RHEL6/7/8
# crash-gcore-cmd only support x86_64 and i386/i686 on RHEL6.
# crash-gocre-cmd support on ppc64/ppc64le was added since RHEL7.1
if [ "${K_ARCH}" == "s390x" ]; then
    Skip "Crash-gcore-command is not supported on ${K_ARCH}."
    Report
elif [ "${IS_RHEL6}" = true ]; then
    grep -q 86 <<< "${K_ARCH}" || {
        Skip "Crash-gcore-command is not supported on ${K_ARCH} on RHEL6."
    }
    Report
else
    Log "Crash-gcore-command is supported on ${K_ARCH}, continue test."
fi


RemoveTempFiles()
{
    Log "Clean up temp files"
    rm -f "$(pwd)/core.$pid.$proc"
    rm -f "${K_TESTAREA}/pid.cmd"
    rm -f "${K_TESTAREA}/pid.output"
    rm -f "${K_TESTAREA}/gcore.cmd"
    rm -f "${K_TESTAREA}/gdb.output"
}

Analyse()
{
    PrepareCrash
    PACKAGE_NAME="crash-gcore-command"
    LogRun "rpm -q $PACKAGE_NAME gdb trace-cmd" || InstallPackages $PACKAGE_NAME gdb trace-cmd
    rpm -q --quiet $PACKAGE_NAME || {
        Error "$PACKAGE_NAME is not installed."
        return
    }
    CheckVmlinux

    RemoveTempFiles

    [ "${TESTARGS,,}" = "loadtestonly" ] && {
        Log "- Test loading of crash-gcore plugin"
        CrashExtensionLoadTest gcore
        return
    }

    GetCorePath

    Log "Run gcore against the vmcore"
    Log "Get the PID of the last process"
    cat <<EOF > "${K_TESTAREA}/pid.cmd"
bt | grep "PID"
q
EOF
    # shellcheck disable=SC2154
    Log "# crash $vmlinux $vmcore -s -i \"${K_TESTAREA}/pid.cmd\""
    crash $vmlinux $vmcore -s -i "${K_TESTAREA}/pid.cmd" > "${K_TESTAREA}/pid.output" 2>&1
    RhtsSubmit "${K_TESTAREA}/pid.cmd"
    RhtsSubmit "${K_TESTAREA}/pid.output"

    pid=$(grep "PID" "${K_TESTAREA}/pid.output" | awk '{print $2}')
    proc=$(grep "PID" "${K_TESTAREA}/pid.output" | awk '{print $8}'|cut -d\" -f2)
    Log "crash pid: $pid"
    Log "crash proc: $proc"

    Log "Feed the PID: ${pid} to gcore command"
    cat <<EOF > "${K_TESTAREA}/gcore.cmd"
extend gcore.so
help -e
bt ${pid}
gcore ${pid}
q
EOF
    RhtsSubmit "${K_TESTAREA}/gcore.cmd"

    CrashCommand "" "${vmlinux}" "${vmcore}" "gcore.cmd"
    [ -f "core.$pid.$proc" ] || Error "File core.$pid.$proc is not generated."

    # Run smoke test with gdb
    Log "Run gdb smoke test ."
    LogRun "rpm -q gdb" || InstallPackages gdb
    gdb $(which bash) core.$pid.$proc --quiet -ex q > "${K_TESTAREA}/gdb.output"
    RhtsSubmit "${K_TESTAREA}/gdb.output"

    RemoveTempFiles

}

Multihost Analyse
