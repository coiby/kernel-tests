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
	rlPass "modprobe -r null_blk"
	rlRun "modprobe null_blk queue_mode=2 gb=10 use_per_node_hctx=1"
	sleep 2

	for pattern in read write randread randwrite readwrite randrw; do
		for i in 4 8 16 32 64 128 256 512 1024; do
			echo "Pattern: $pattern  Block size: $i"k"" | tee /dev/kmsg
				rlRun "fio --bs=$i"k" --ioengine=libaio --iodepth=1024 --numjobs=4 \
					--rw=$pattern --name=async --filename=/dev/nullb0 \
					--size=10g --direct=1 --ioscheduler=none &> /dev/null"
				sync
				echo 3 > /proc/sys/vm/drop_caches
				sleep 10
		done
	done
	rlRun "modprobe -r null_blk"
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
