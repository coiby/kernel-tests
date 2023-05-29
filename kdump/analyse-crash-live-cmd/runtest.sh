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

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0

if ! (($is_rhivos)); then
    # Include rhts environment
    . /usr/bin/rhts-environment.sh || exit 1
fi

# Source Kdump tests common functions.
. ../include/runtest.sh

CheckUnexpectedReboot

TESTARGS=${TESTARGS:-"analyse-crash-common.sh"}
SKIP_TESTARGS=${SKIP_TESTARGS:-""}

PrepareCrash

# Clean up crash cmd files generated for each test run.
CleanCMD(){
    rm -f "${K_TESTAREA}/crash"*.cmd
}

# Run Sub tests under testcases
RunSubTests "${TESTARGS}" "${SKIP_TESTARGS}"



