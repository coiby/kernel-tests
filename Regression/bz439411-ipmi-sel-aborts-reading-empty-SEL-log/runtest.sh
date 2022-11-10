#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/freeipmi/Regression/bz439411-ipmi-sel-aborts-reading-empty-SEL-log
#   Description: Test for bz439411 (ipmi-sel aborts reading empty SEL log)
#   Author: Rachel Sibleyr <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2011 Red Hat, Inc. All rights reserved.
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
. /usr/bin/rhts-environment.sh
. /usr/lib/beakerlib/beakerlib.sh

export PACKAGE="freeipmi"

rlJournalStart

    rlPhaseStartTest "test the bug"
	rlRun "ipmi-sel --clear"
    rlPhaseEnd

    rlPhaseStartTest "test the bug, phase A"
# old version behaves differently in the loop
	for i in $(seq 1 100);do
		rlRun "ipmi-sel" 0-128 "no segfault"
	done
    rlPhaseEnd

    rlPhaseStartTest "test the bug, phase B"
# see if the messages are OK
        rlRun "ipmi-sel &> log" 0-128 "no segfault"
        grep 'unable to get SEL record' log
	rlAssertEquals "unable to get SEL record" $? 0
    rlPhaseEnd

    rlPhaseStartCleanup "clean up"
	rm -rf log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
