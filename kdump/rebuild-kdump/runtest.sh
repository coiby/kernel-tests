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

# kdump rebuild support is added to rhel8 since kexec-tools-2.0.19-1.el8
# Bug 1688687: RFE kdumpctl: add rebuild support

RebuildKdumpTest()
{
    kdumpctl status
    RhtsSubmit "$KDUMP_CONFIG"

    kdumpctl rebuild
    retval=$?
    if [ "$retval" -ne 0 ]; then
        MajorError "- Rebuilding kdump initramfs image failed!"
    fi

    ReportKdumprd
}

Multihost "RebuildKdumpTest"
