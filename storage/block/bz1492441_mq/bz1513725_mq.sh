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

function setup()
{  
	rm -rf /etc/multipath.conf
	mpathconf --disable
	systemctl stop multipathd
	systemctl disable multipathd
	rmmod scsi_debug -f
}

function run_test()
{
	rlRun "modprobe scsi_debug"
	sleep 2

	DEVICE=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename`

	DISK_DIR=`ls -d /sys/block/$DEVICE/device/scsi_disk/*`

	rlLog "using scsi device $DEVICE"
	echo "-1" >/sys/bus/pseudo/drivers/scsi_debug/every_nth
	for i in `seq 1 1`; do
		rlLog "starting loop $i"
		echo "temporary write through" >$DISK_DIR/cache_type
		echo "128" >/sys/bus/pseudo/drivers/scsi_debug/opts
		dd if=/dev/$DEVICE of=/dev/null bs=1M iflag=direct count=1 &
		sleep 5
		echo "1" >/sys/block/$DEVICE/device/delete
		echo "0" >/sys/bus/pseudo/drivers/scsi_debug/opts
		wait
		rlLog "ending loop $i"
	done
	rmmod scsi_debug -f > /dev/null 2>&1
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
		setup
		run_test
		check_log
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
