#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: admin_reserve_kbytes is initialized to min(3% free pages, 8MB)
#   Author: Li Wang <liwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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

PACKAGE="kernel"

rlJournalStart
	rlPhaseStartSetup
		rlAssertRpm $PACKAGE
	rlPhaseEnd

	rlPhaseStartTest
	if rlIsRHEL ">=7.0" || rlIsFedora; then
		rlRun "./check-admin_reserve_kbytes.sh" 0,2 "Executing Testing, return 2 means skipped."
		rlRun "./check-user_reserve_kbytes.sh" 0 "Executing Testing"
	# Until now, RHEL6 has not apply the user_reserve_kbytes patch
	elif rlIsRHEL 6; then
		rlRun "./check-admin_reserve_kbytes.sh" 0,2 "Executing Testing, return 2 means skipped."
	else
		rstrnt-report-result Test_Skipped PASS 99
		exit 0
	fi
	rlPhaseEnd

	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
