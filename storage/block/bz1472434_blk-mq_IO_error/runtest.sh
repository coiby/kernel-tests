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

function run_test()
{
	rlRun "cat /sys/module/scsi_mod/parameters/use_blk_mq"
	value=$(cat /sys/module/scsi_mod/parameters/use_blk_mq)
	if [ "$value" == "Y" ];then
		rlLog "scsi-mq has enable in kernel"
	else
		rlLog "scsi-mq don't enable ,please add scsi_mod.use_blk_mq=1 to kernel"
		exit 1
	fi

	lsscsi -g |grep scsi_debug
	if [ $? = 0 ]; then
		rlLog "scsi_debug have installed,we need remove first"
		rlRun "rmmod scsi_debug"
	fi

	rlRun "modprobe scsi_debug delay=100"
	sleep 10
	lsscsi -g

	DEV=$(lsscsi -g |grep scsi_debug |awk '{print $6}')
	DEV=${DEV##*/}
	chmod +x code.sh
	sh code.sh $DEV

	if [ $? = 0 ];then
		rlLog "#### have passed "
	else
		rlLog "test failed"
	fi
	rlRun "rmmod  scsi_debug -f"
}

function check_log()
{
	rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
	rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
	rlRun "dmesg | grep -i 'BUG:'" 1 "check the errors"
	rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
}

rlJournalStart
	rlPhaseStartTest
		rlRun "dmesg -C"
		rlRun "uname -a"
		rlLog "$0"
		run_test
		check_log
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
