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
        if [ ! -f /var/log/audit/audit.log ]; then
            rlLog "audit.log not found. Skipping test."
            rstrnt-report-result Test_Skipped PASS 99
            rlPhaseEnd
            rlJournalPrintText
            rlJournalEnd
            exit 0
        fi
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "nft add table t; "
        rlRun "grep 'type=NETFILTER_CFG' /var/log/audit/audit.log | tee audit.log_old"
        rlRun "nft 'add chain t c; add rule t c accept'"
        rlRun "nft list table t"
        rlRun "grep 'type=NETFILTER_CFG' /var/log/audit/audit.log | tee audit.log_new"
        rlRun "diff audit.log_old audit.log_new" 1
        rlRun "entries=$(diff audit.log_old audit.log_new | grep 'type=NETFILTER_CFG' | wc -l)"
        # shellcheck disable=SC2154
        rlAssertEquals "Test pass: only single entry log for all calls" "$entries" 1
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "nft delete table t"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
