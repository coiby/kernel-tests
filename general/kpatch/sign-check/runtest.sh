#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/kpatch/sign-check
#   Description: Test to check for kpatch module signature
#   Author: Yulia Kopkova <ykopkova@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh

KPATCH_PATCH="${KPATCH_PATCH:-}"
KPATCH_MODULE=$(echo ${KPATCH_PATCH} | sed -e "s/kpatch-patch/kpatch/" | sed -e "s/\.el.*//" | sed -e "s/-/_/g")

rlJournalStart
    rlPhaseStartSetup
        [[ -z "${KPATCH_PATCH}" ]] && rlDie "KPATCH_PATCH is not set. Aborting test execution"

        rlRun "kpatch force unload --all"
        rlRun "kpatch load ${KPATCH_MODULE}"
        rlRun "lsmod | grep ${KPATCH_MODULE}" 0 "${KPATCH_MODULE} is loaded"
    rlPhaseEnd

    rlPhaseStartTest "kpatch module check"
        rlRun "kpatch info ${KPATCH_MODULE} | grep 'Red Hat Enterprise Linux kpatch signing key'" 0 "patch module is signed"

        tainted=$(cat /proc/sys/kernel/tainted)
        rlRun "cat /proc/sys/kernel/tainted" -l 0-255
        rlRun -l "dmesg | grep kpatch" 0-254

        # TAINT_OOT_MODULE bit 12; TAINT_LIVEPATCH bit 15
        rlRun "(( ($tainted >> 12) & 1 ))" 0 "TAINT_OOT_MODULE bit is set"
        rlRun "(( ($tainted >> 15) & 1 ))" 0 "TAINT_LIVEPATCH bit is set"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
