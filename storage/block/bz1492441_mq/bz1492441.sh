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

	DEVNAME=`find /sys/bus/pseudo/devices/adapter0/ -name block`
	DEVNAME=`ls $DEVNAME`

	DEVHOST=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*`
	DEVHOST=`basename $DEVHOST`

	FLAGFILE=`mktemp /tmp/change_iosched_XXXXX`
	while [ -f $FLAGFILE ]; do
		echo "mq_deadline" >/sys/block/$DEVNAME/queue/scheduler >/dev/null 2>&1
		echo "bfq" >/sys/block/$DEVNAME/queue/scheduler >/dev/null 2>&1
	done &

	while [ -f $FLAGFILE ]; do
		echo "1" >/sys/block/$DEVNAME/device/delete >/dev/null 2>&1
		sleep 0.1
		echo "- - -" >/sys/bus/pseudo/drivers/scsi_debug/adapter0/$DEVHOST/scsi_host/$DEVHOST/scan  >/dev/null 2>&1
		sleep 0.1
	done &

	sleep 600
	rm -f "$FLAGFILE"
	wait
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
