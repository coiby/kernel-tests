#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        if rlIsRHEL '<9'; then
            echo "[SKIP] support RHEL9 or later"
            rstrnt-report-result $RSTRNT_TASKNAME SKIP
            exit 0
        fi
        rlRun "keyctl show %:.ima | tee /tmp/.ima"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "modinfo libcrc32c | tee /tmp/.modinfo"
        rlAssertGrep "$(modinfo -F signer libcrc32c)" /tmp/.ima
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileSubmit /tmp/.ima
        rlFileSubmit /tmp/.modinfo
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
