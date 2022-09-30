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
source $CDIR/../../../cki_lib/libcki.sh     || exit 1
. /usr/share/beakerlib/beakerlib.sh         || exit 1

rlJournalStart
	rlPhaseStartSetup Setup
		rlPass "mpathconf --disable && service multipathd reload"
		rlPass "modprobe -r scsi_debug"
		rlRun "lsblk"
	rlPhaseEnd

	rlPhaseStartTest bz1492441.sh
		rlLog "will run case bz1492441.sh"
		chmod a+x bz1492441.sh
		sh bz1492441.sh
	rlPhaseEnd

	rlPhaseStartTest bz1513036.sh
		rlLog "will run case bz1513036.sh"
		chmod a+x bz1513036.sh
		sh bz1513036.sh
	rlPhaseEnd

	rlPhaseStartTest bz1513725_mq.sh
		rlLog "will run case bz1513725_mq.sh"
		chmod a+x bz1513725_mq.sh
		sh bz1513725_mq.sh
	rlPhaseEnd

	rlPhaseStartTest bz1523029.sh
		rlLog "will run case bz1523029.sh"
		chmod a+x bz1523029.sh
		sh bz1523029.sh
	rlPhaseEnd

	rlPhaseStartTest bz1614305.sh
		rlLog "will run case bz1614305.sh"
		chmod a+x bz1614305.sh
		sh bz1614305.sh
	rlPhaseEnd

	rlPhaseStartTest bz1648750.sh
		rlRun "will run case bz1648750.sh"
		chmod a+x bz1648750.sh
		sh bz1648750.sh
	rlPhaseEnd

	rlPhaseStartCleanup Cleanup
		rlRun "rmmod scsi_debug -f"
	rlPhaseEnd
rlJournalPrintText
