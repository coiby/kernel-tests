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

# Bug 1966881 - kdump service restart throws a bash script error when KDUMP_KERNELVER is set
# Fixed in RHEL-8.5 kexec-tools-2.0.20-57.el8.
CheckSkipTest kexec-tools 2.0.20-57 && Report

RegressionTest() {
    AppendSysconfig "KDUMP_KERNELVER" "add" "$(uname -r)" "" && RestartKdump
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC RegressionTest

