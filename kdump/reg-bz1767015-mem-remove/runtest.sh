#!/bin/sh

# Copyright (c) 2018 Red Hat, Inc. All rights reserved.
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

#  Author: Xiaowu Wu    <xiawu@redhat.com>
#  Update: Ruowen Qin   <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1767015 - kdump service becomes "Not Operational" after memory remove operation
# Fixed in RHEL-8.2 kexec-tools-2.0.20-14.el8 (ppc64le only)
# Bug 1797848 - [ppc64le] Kdump failed to generate vmcore if panic triggered after
#               removing memory: "get_mem_section: Could not validate mem_section"
# Fixed in RHEL-8.2 kernel-4.18.0-177.el8
[[ "${K_ARCH}" != ppc64le ]] && {
    Skip "Test is applicable on ppc64le only"
    Report
}
CheckSkipTest kexec-tools 2.0.20-14 && Report
CheckSkipTest kernel 4.18.0-177 && Report

TESTARGS=${TESTARGS:-"10"}
LOOPCOUNT=${LOOPCOUNT:-"10"}

AddAndRemoveMem() {

    which drmgr >/dev/null 2>&1 || InstallPackages powerpc-utils
    LogRun "rpm -q powerpc-utils"

    # Bug 1787269 - Memory DLPAR, LPAR crashes
    Log "Test 1 - Check if kdump is operational after removing/adding LMB repeatedly ($LOOPCOUNT times)"
    local i=1
    for ((i=1; i<="$LOOPCOUNT"; i++)); do
        Log "Try #$i"

        LogRun "lsmem"
        # remove multiple LMB (by default, 10 LMB = 2.5G)
        Log "Remove $TESTARGS LMB"
        LogRun "drmgr -c mem -r -q ${TESTARGS}" || MajorError "Failed to remove mem by drmgr"
        kdumpctl status || {
            MajorError "Kdump is not operational after removing memory"
            UploadJournalLogs
        }

        LogRun "lsmem"
        # add multiple LMB (by default, 10 LMB = 2.5G)
        Log "Add $TESTARGS LMB"
        LogRun "drmgr -c mem -a -q ${TESTARGS}" || MajorError "Failed to add mem by drmgr"
        kdumpctl status || {
            MajorError "Kdump is not operational after adding memory"
            UploadJournalLogs
        }
        LogRun "lsmem"

        ((i++))
    done

    # Test Kdump after removing memory
    Log "Test 2 - Panic test after removing memory"
    LogRun "lsmem"
    # remove multiple LMB (by default, 10 LMB = 2.5G)
    Log "Remove $TESTARGS LMB"
    LogRun "drmgr -c mem -r -q ${TESTARGS}" || MajorError "Failed to remove mem by drmgr"
    LogRun "kdumpctl status" || {
        MajorError "Kdump is not operational after removing memory"
        UploadJournalLogs
    }
    LogRun "lsmem"

}
# --- start ---
Multihost SystemCrashTest TriggerSysrqC AddAndRemoveMem
