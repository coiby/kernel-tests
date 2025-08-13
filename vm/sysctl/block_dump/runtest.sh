#!/bin/bash

# Copyright (c) 2011 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Zhouping Liu <zliu@redhat.com>

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Include some helpers
. ../include/runtest.sh

OLD_BLOCK_DUMP=
TUNE_FILE="/proc/sys/vm/block_dump"
TMP_FILE=`mktemp /tmp/block.XXXXXX`

function block_dump_test()
{
	dmesg -c  > /dev/null
	echo 1 > ${TUNE_FILE}
	verify_tune_value ${TUNE_FILE} 1

	dd if=/dev/zero of=${TMP_FILE} bs=1024k count=1
	sleep 1

	ls -l /dev/ > ${TMP_FILE}
	sleep 1

	if [ -f $TMP_FILE ]; then
		rlLog TestPASS: block_dump PASS
		rm ${TMP_FILE}*
	else
		rlLog TestError: block_dump FAIL
		exit 1
	fi
}

function main()
{
rlJournalStart
	rlPhaseStartSetup
	local rhel=$(grep -Eo '[0-9]+.[0-9]+' /etc/redhat-release)
	if (echo ${rhel} "9.0" | awk '($1<$2){exit 1}') then
		echo "block_dump has been dropped from RHEL9" | tee -a $OUTPUTFILE
		rstrnt-report-result block_dump_not_support_from_rhel9 SKIP
		rlPhaseEnd
		rlJournalEnd
		exit 0
	fi
	rlPhaseEnd

	rlPhaseStartTest
	check_file_exist ${TUNE_FILE}
	OLD_BLOCK_DUMP=`cat ${TUNE_FILE}`

	block_dump_test
	echo ${OLD_BLOCK_DUMP} > ${TUNE_FILE}
	rlPhaseEnd
	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
}

main
