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
. /usr/share/beakerlib/beakerlib.sh		|| exit 1

function run_test()
{
# Consume memory, keep machine low memory
	rlRun "free -g"
	available_mem=$(free -g | awk 'NR>1 {print $NF}' | awk 'NR==1{print}')
	a=$(expr $available_mem - 4)
	scsi_debug_size=$(expr $a \* 1000)

	rlLog "Original performance"
	rlRun "time rpm -qa | wc -l"

	rlRun "modprobe scsi_debug dev_size_mb=$scsi_debug_size"
	rlRun "lsblk"

	dev=$(lsblk |grep boot | awk '{print $1}' | grep -oE "[a-z]{3,}" | sed -n '1p')
	rlRun "cat /sys/kernel/debug/block/$dev/state"
	rlLog "Original dirty page configuration"
	rlRun "sysctl -a -r dirty"
	dirty_background_ratio=$(sysctl -a -r dirty | grep vm.dirty_background_ratio | awk -F "=" '{print $2}' | sed 's/^[ \t]*//g')
	dirty_ratio=$(sysctl -a -r dirty | grep vm.dirty_ratio | awk -F "=" '{print $2}' | sed 's/^[ \t]*//g')

	rlLog "dirty_ratio=10"
	echo 10 > /proc/sys/vm/dirty_ratio
	echo 0 > /proc/sys/vm/dirty_background_ratio
	echo 3 > /proc/sys/vm/drop_caches
	rlRun "sysctl -a -r dirty"

	rlRun 'date +"%Y-%m-%d %H:%M:%S"'
	begin=$(date +"%S")

	rlRun "time rpm -qa | wc -l"

	end=$(date +"%S")
	rlRun 'date +"%Y-%m-%d %H:%M:%S"'

	result=$(expr $end - $begin)
	[[ $result -lt 4 ]] || rlFail "test fail,please check"

	rlLog "dirty_ratio=10;dirty_background_bytes=5"
	echo 5 > /proc/sys/vm/dirty_background_bytes
	echo 3 > /proc/sys/vm/drop_caches
	rlRun "sysctl -a -r dirty"
	rlRun 'time for i in $(seq 0 999); do xfs_io -fc "pwrite 0 1m" ./file > /dev/null; done'
	sleep 3

	rlLog "Restoring dirty page configuration"
	rlRun "sysctl vm.dirty_ratio=$dirty_ratio"
	rlRun "sysctl vm.dirty_background_ratio=$dirty_background_ratio"
	rlRun "sysctl -a -r dirty"
	rlRun "rmmod scsi_debug -f"
	wait
}

function check_log()
{
	rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
	rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
	rlRun "dmesg | grep 'BUG:'" 1 "check the errors"
	rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
}

rlJournalStart
	rlPhaseStartTest
		rlRun "dmesg -C"
		rlRun "uname -a"
		rlLog "$0"
		rmmod scsi_debug -f
		run_test
		check_log
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
