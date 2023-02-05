#!/bin/sh

# Copyright (C) 2008 CAI Qian <caiqian@redhat.com>
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

# Kdump reload is supported since RHEL7.7/8.0

# Added to rhel7.7 since kexec-tools-2.0.15-22.el7
# Bug 1640065 - [Hyper-V][RHEL7.6]Error applying Memory changes to larger size

# Added to rhel8.0 since kexec-tools-2.0.17-19.el8
# Bug 1647722 - [Hyper-V][RHEL8.0]Error applying Memory changes to larger size

ReloadKdumpTest()
{
    kdumpctl status
    RhtsSubmit "$KDUMP_SYS_CONFIG"
    ReportKdumprd

    systemctl reload kdump
    retval=$?
    journalctl -u kdump > "${K_TESTAREA}/kdump.messages.log"
    sync
    RhtsSubmit "${K_TESTAREA}/kdump.messages.log"

    if [ "$retval" -ne 0 ]; then
        Error "- 'systemctl reload kdump' failed"
        # try again with kdumpctl
        kdumpctl reload
        retval=$?
        journalctl -u kdump > "${K_TESTAREA}/kdump.messages.log"
        sync
        RhtsSubmit "${K_TESTAREA}/kdump.messages.log"
        if [ "$retval" -ne 0 ]; then
            MajorError "- 'kdumpctl reload' failed"
        fi
    fi
}

Multihost "ReloadKdumpTest"

