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

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "${FILE}")

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh		|| exit 1
. /usr/share/beakerlib/beakerlib.sh			|| exit 1

function run_test()
{
# Clone and install NBD from upstream
	[ ! -d nbd ] && rlRun "git clone -b nbd-3.25 https://gitlab.com/redhat/centos-stream/tests/kernel/storage/nbd.git"
	rlRun "cd nbd"
	rlRun "./autogen.sh > /dev/null 2>&1"
	rlRun "./configure > /dev/null 2>&1"
	rlRun "make > /dev/null 2>&1"
	rlRun "make install > /dev/null 2>&1"
# Load nbd module and ckeck nbd process
	rlRun "modprobe nbd"
	rlRun "ps -ef | grep nbd"

	[ -f /tmp/socket ] && rlRun "rm /tmp/socket"

# Create a RAM disk
	rlRun "nbdkit -U /tmp/socket memory 2G"
	rlRun "nbd-client -unix /tmp/socket /dev/nbd0 -b 512"
	rlRun "lsblk"

# Queries whether /dev/nbd0 is attached or not
	rlRun "nbd-client -c /dev/nbd0"

# Create filesystem and mount it
	[ ! -d /tmp/mnt ] && rlRun "mkdir /tmp/mnt"
	for fstype in ext2 ext3 ext4 xfs; do
		if [[ $fstype == "xfs" ]];then
			rlRun "mkfs -t $fstype -f /dev/nbd0"
		else
			rlRun "mkfs -t $fstype -F /dev/nbd0"
		fi
		rlRun "mount /dev/nbd0 /tmp/mnt"
		rlRun "dd if=/dev/zero of=/tmp/mnt/file1 bs=1M count=1000"
		[ -f /tmp/mnt/file1 ] && rlLog "$fstype Test Pass" || rlLog "$fstype Test Fail"
		rlRun "rm -rf /tmp/mnt/file1"
		rlRun "umount /tmp/mnt"
	done

# Detaches /dev/nbd0
	rlRun "nbd-client -d /dev/nbd0"
	rlRun "rmmod nbd"
	rlRun "rm /tmp/socket"
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
