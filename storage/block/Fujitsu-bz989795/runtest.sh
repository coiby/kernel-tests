#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh		|| exit 1
. /usr/share/beakerlib/beakerlib.sh			|| exit 1

PACKAGE="kernel"

rlJournalStart
	rlPhaseStartSetup
		rlAssertRpm $PACKAGE
		rlAssertRpm "device-mapper" || exit 1
		export LC_MESSAGES="en_US.UTF-8"
	rlPhaseEnd

	rlPhaseStartTest
		rlRun "./using_unassigned_loop_device.sh" 0 "Executing reproducer"
		if [ $? -eq 2 ]; then
			rlLogWarning "Failed without reproducing the problem: Unexpected Error occured"
		fi
	rlPhaseEnd

	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
