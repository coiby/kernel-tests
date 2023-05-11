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

NOKDUMPRD=${NOKDUMPRD:-false}

RestartKdumpTest()
{
    Log "Print rpm packages and kernel/crash status"
    LogRun "rpm -q kexec-tools kernel"
    LogRun "uname -r"
    LogRun "cat /proc/cmdline"
    LogRun "cat /sys/kernel/kexec_crash_size"

    Log "Submit kdump configurations"
    RhtsSubmit "$KDUMP_CONFIG"
    RhtsSubmit "$KDUMP_SYS_CONFIG"

    RestartKdump
}

Multihost "RestartKdumpTest"
