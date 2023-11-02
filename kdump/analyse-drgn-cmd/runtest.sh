#!/bin/sh

# Copyright (c) 2023 Red Hat, Inc. All rights reserved.
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

TESTARGS=${TESTARGS:-"basic"}
SKIP_TESTARGS=${SKIP_TESTARGS:-""}
TESTTYPE=${TESTTYPE:-"live"}

analyse() {
    testtype=$1
    testcase=$2
    CMD="drgn"

    tc=$(basename "${testcase}")
    ext_opts=""

    CheckVmlinux
    if [ "${testtype}" == "vmcore" ]; then
        GetCorePath
        ext_opts="-c ${vmcore}"
    fi

    _log1="${K_TESTAREA}/${tc}-${testtype}.log"
    _log2="${K_TESTAREA}/${tc}-${testtype}.err.log"
    [ -f "${_log1}" ] && rm -f "${_log1}"
    [ -f "${_log2}" ] && rm -f "${_log2}"

    LogRun "${CMD} ${ext_opts} ${testcase} >${_log1} 2>${_log2}"
    RhtsSubmit "${_log1}"
    RhtsSubmit "${_log2}"
    [ -s "${_log2}" ] && Error "Please check ${_log2} for errors"

}

RunDrgnTests(){
    TESTARGS=$1
    SKIP_TESTARGS=${2:-"NOEXISTCASE"}
    TESTTYPE=$3

    Log "================================="
    Log "  Test setup"
    Log "================================="

    TmpDir=$(mktemp -d -p .)
    cp -r testcases/* "$TmpDir"
    Log "Copy to tmp directory: ${TmpDir}"

    # Run tests specified in arg "TESTARGS". Otherwise run all py scripts defined in
    # in subdirectory testcases. Tests specified in arg "SKIP_TESTARGS" will always be
    # skipped.
    # If multiple script names are provided in TESTARGS or SKIP_TESTARGS, script names
    # should be separated by comma.
    # if the arg "TESTARGS" is "all", run all sh scripts defined in subdirectory testcases
    # e.g. TESTARGS="basic.py"
    # Valid "TESTTYPE" values are "live", "vmcore", any other values will be treated as "live"
    # by default.

    [ "TEST${TESTTYPE}" == "TEST" ] || [ "${TESTTYPE,,}" != "vmcore" ] && [ "${TESTTYPE,,}" != "live" ] && {
        TESTTYPE="live"
    }

    local all_tests=$(find testcases/ -name "*.py" -printf "%f\n")
    if [ "TEST${TESTARGS}" == "TEST" ] || [ ${TESTARGS,,} == "all" ]; then
        TESTARGS="all"
    else
        TESTARGS="$(echo ${TESTARGS} | sed -r 's/[, ]+/|/g;s/\|+$//g;s/^\|+//g')"
    fi
    SKIP_TESTARGS="$(echo ${SKIP_TESTARGS} | sed -r 's/[, ]+/|/g;s/\|+$//g;s/^\|+//g')"

    # Note, there is no handling of system reboot in this runtest.sh.
    for subcase in ${all_tests}; do
        tmp_subcase=$(basename "${subcase}")
        if [ "${TESTARGS,,}" != "all" ] && ! grep -E -q "${TESTARGS}" <<< "${tmp_subcase}"; then
            # Not in TESTARGS list.Ignore the test
            continue
        fi

        Log "============================================="
        Log "  #Sub Test# ${TESTTYPE} $subcase"
        Log "============================================="
        if grep -E -q "${SKIP_TESTARGS}" <<< "${tmp_subcase}"; then
            Log "Skip test: ${subcase}"
            continue
        elif [ ! -f "testcases/${subcase}" ]; then
            Warn "Skip test ${subcase}: No such file or directory"
            continue
        fi

        Log "Execute ${TmpDir}/${subcase}"
        Multihost analyse "${TESTTYPE}" "${TmpDir}/${subcase}"
    done

    Log "================================="
    Log "  Test cleanup"
    Log "================================="

    Log "Removing tmp directory $TmpDir"
    rm -rf "$TmpDir"

}

PrepareDrgn || {
    Skip "Test is only applicable to RHEL9.4 or later releases"
    Report
    return
}

# Run Sub tests under testcases
RunDrgnTests "${TESTARGS}" "${SKIP_TESTARGS}" "${TESTTYPE}"



