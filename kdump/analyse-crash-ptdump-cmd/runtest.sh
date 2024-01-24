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

TESTARGS=${TESTARGS:-""}

Analyse()
{
    # crash-ptdump-cmd is only supported on RHEL7/8
    if [ "${IS_RHEL8}" != true ] && [ "${IS_RHEL7}" != true ]; then
        Skip "Crash-ptdump-command is only supported in RHEL7/8."
        return
    fi

    PrepareCrash
    PACKAGE_NAME="crash-ptdump-command"
    LogRun "rpm -q $PACKAGE_NAME" || InstallPackages $PACKAGE_NAME
    rpm -q --quiet $PACKAGE_NAME || {
        Error "$PACKAGE_NAME is not installed."
        return
    }

    CheckVmlinux

    [ "${TESTARGS,,}" = "loadtestonly" ] && {
        CrashExtensionLoadTest ptdump
        return
    }

    GetCorePath

    # Only check the return code of this session.
    # N/A
    rm -f /root/ptdump
    # Also check command output of this session
    cat <<EOF >>"${K_TESTAREA}/crash.cmd"
extend ptdump.so
help ptdump
ptdump /root/ptdump
ls /root/ptdump
exit
EOF

    # shellcheck disable=SC2154
    CrashCommand "" "${vmlinux}" "${vmcore}"

    local count
    count=$(ls -l /root/ptdump | wc -l)
    [ "$count" == 1 ] && MajorError "No log buffer generated in /root/ptdump"
}

#+---------------------------+
Multihost "Analyse"
