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

# BPF command is added in RHEL-7.6 and RHEL-8.0
# Bug 1559758 - [RHEL7] crash needs to allow extraction of BPF programs from the vmcore
# crash-7.2.3-8.el7 (Fixed in crash-7.2.3-6.el7)
# Bug 1572524 - [RHEL8] crash needs to allow extraction of BPF programs from the vmcore
# crash-7.2.3-18.el8 (Fixed in crash-7.2.3-4.el8+7)


# Source Kdump tests common functions.
. ../include/runtest.sh

TESTARGS=${TESTARGS:-""}
SKIP_TESTARGS=${SKIP_TESTARGS:-""}

PrepareCrash

CheckSkipTest crash 7.2.3-6 && Report

# Clean up crash cmd files generated for each test run.
CleanCMD(){
    [ -f "${K_TESTAREA}/crash-bpf-simple.cmd" ] && "rm -f ${K_TESTAREA}/crash-bpf-simple.cmd"
    [ -f "${K_TESTAREA}/crash-bpf.cmd" ] && rm -f "${K_TESTAREA}/crash-bpf.cmd"
}

# Run Sub tests under testcases
RunSubTests "${TESTARGS}" "${SKIP_TESTARGS}"




