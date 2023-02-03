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
	rlPhaseEnd

	rlPhaseStartTest
		rlRun "cp /etc/audit/rules.d/audit.rules ./audit_original.rules"
		rlRun "echo -e '--loginuid-immutable\n-w /root/aaa -p wrx' >> /etc/audit/rules.d/audit.rules"
		rlRun "sed -i 's/^-b.*$/-b 64/g' /etc/audit/rules.d/audit.rules"
	rlRun "service auditd restart"
	pid=$(pgrep -f "[s]bin/auditd")
	rlRun "kill -19 $pid"
	rlRun "chmod +x repro.sh"
	rlWatchdog "./repro.sh" 15
	if [[ $? -eq 0 ]]; then
		rlPass "Process did not hang, test pass."
	else
		rlFail "Process hung, test fail."
	fi
	rlPhaseEnd

	rlPhaseStartCleanup
	rlRun "cat ./audit_original.rules > /etc/audit/rules.d/audit.rules"
	rlRun "rm -f ./audit_original.rules"
	rlRun "kill -18 $pid"
	rlRun "service auditd restart"
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
