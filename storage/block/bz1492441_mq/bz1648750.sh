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
	lsblk | grep zram
	if [ $? == 0 ];then
		rlLog "need remove swap frist"
		swap_size=$(lsblk | grep zram0 | awk -F " " '{print $4}')
		rlRun "swapoff /dev/zram0"
		rlRun "echo 0 > /sys/class/zram-control/hot_remove"
		rlRun "rmmod zram"
		rlRun "lsblk"
	else
		rlLog "no zram device as swap,no need do setup"
	fi

	modprobe -r zram
	rlRun "modprobe zram"
	echo zstd > /sys/block/zram0/comp_algorithm
	echo 8297508864 > /sys/block/zram0/disksize
	rlRun "mkswap /dev/zram0"
	rlRun "swapon -d -p 100 /dev/zram0"
	rlRun "lsblk"
	sleep 10
	rlRun "swapoff /dev/zram0"
	rlRun "lsblk"

	modprobe -r zram
	rlRun "modprobe zram"
	echo 8297508864 > /sys/block/zram0/disksize
	rlRun "blkdiscard /dev/zram0"
	sleep 3
	[[ -z $swap_size ]] || restore_swap
}

function restore_swap()
{
	rlRun "modprobe -v zram"
	rlRun "echo zstd > /sys/block/zram0/comp_algorithm"
	rlRun "echo 4G > /sys/block/zram0/disksize"
	rlRun "mkswap /dev/zram0"
	rlRun "swapon /dev/zram0"
	rlRun "lsblk"
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
