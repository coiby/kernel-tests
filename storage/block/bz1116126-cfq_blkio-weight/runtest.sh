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
	rlLog "running $0"
	rlLog "create the scsi_debug 4k sector disk"
	rlRun "modprobe -r scsi_debug"
#trun "lsmod |grep scsi_debug"
	rlRun "modprobe scsi_debug dev_size_mb=1000 "
	sleep 5
	DEVICE=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename`
	echo "bfq" >/sys/block/$DEVICE/queue/scheduler
	mkdir -p /sys/fs/cgroup/blkio/testgroup1/testgroup2
	echo 500 > /sys/fs/cgroup/blkio/testgroup1/blkio.weight
#start a dd in testgroup2
	echo $$ >/sys/fs/cgroup/blkio/testgroup1/testgroup2/tasks
	dd if=/dev/$DEVICE of=/dev/null bs=1k iflag=direct &
	DD_PID=$!
	echo "$DD_PID dd_pid"

#Now run the rest of I/O operations in testgroup1
	echo $$ >/sys/fs/cgroup/blkio/testgroup1/tasks
	if [ "$?" == "0" ]; then
		dd if=/dev/$DEVICE of=/dev/null bs=1k iflag=direct count=1 >/dev/null 2>&1
		echo 1000 > /sys/fs/cgroup/blkio/testgroup1/blkio.weight
		dd if=/dev/$DEVICE of=/dev/null bs=1k iflag=direct count=1 >/dev/null 2>&1
		echo 500 > /sys/fs/cgroup/blkio/testgroup1/blkio.weight
		fgrep -e $DD_PID /sys/fs/cgroup/blkio/testgroup1/testgroup2/tasks >/dev/null
		echo "test passed" 
		echo "testgroup2 dd stopped, exiting test"
	else
		echo "test failed"
		exit 1
	fi
	sleep 10
	wait
	rlRun "multipath -F"
	rlRun "service multipathd stop"
	rlRun "echo -1 > /sys/bus/pseudo/drivers/scsi_debug/add_host"
	rlRun "modprobe -r scsi_debug || rmmod scsi_debug -f"
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
