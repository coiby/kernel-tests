#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   general/scheduler/runtime_overrun_multithreaded
#   Description: SCHED_DEADLINE runtime overrun signal delivery with service thread
#   Author: Evgeni Vakhonin <evakhoni@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
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

TEST="/kernel-tests/general/scheduler/runtime_overrun_multithreaded"

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../../kernel-include/runtest.sh || exit 1

rlJournalStart
	rlPhaseStartSetup
		rlShowRunningKernel
		if ! rlRun "gcc sigxcpu_thread.c -o sigxcpu_thread"; then
			rstrnt-report-result "$TEST" FAIL
			exit 1
		fi
	rlPhaseEnd

	rlPhaseStartTest "main thread flagged"
		rlRun "./sigxcpu_thread 1" 0 "should get SIGXCPU"
	rlPhaseEnd

	rlPhaseStartTest "main thread not flagged"
		rlRun "./sigxcpu_thread 2" 0 "shouldn't get SIGXCPU"
	rlPhaseEnd

	rlPhaseStartTest "child thread flagged"
		rlRun "./sigxcpu_thread 3" 0 "should get SIGXCPU"
	rlPhaseEnd

	rlPhaseStartTest "child thread not flagged"
		rlRun "./sigxcpu_thread 4" 0 "shouldn't get SIGXCPU"
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "rm -f sigxcpu_thread"
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
