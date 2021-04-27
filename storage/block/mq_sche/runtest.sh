#!/bin/sh                                                                                              
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
source $CDIR/../../../cki_lib/libcki.sh || exit 1

function fio_test()
{
	device=$1
	engine=$2
	sched=$3
	pattern=$4
	is_direct=$5
	depth=$6
	bsize=$7
	sg_gb=$8

	echo "Device: $device  Engine: $engine Sched: $sched Pattern: $pattern " \
		"Direct: $is_direct Depth: $depth " \
		"Block size: ${bsize}K Size: ${sg_gb}G " | tee /dev/kmsg

	rlRun "fio --bs=$bsize"k" --ioengine=$engine --iodepth=$depth --numjobs=4 \
		--rw=$pattern --name=$device-$engine-$pattern-$bsize"k" \
		--filename=/dev/$device --direct=$is_direct --size=${sg_gb}"G" \
		--runtime=60 &> /dev/null"
	wait
	sync
	echo 3 > /proc/sys/vm/drop_caches
	sleep 2
}

function run_test()
{
	echo 4 > /proc/sys/vm/drop_caches
	rmmod scsi_debug > /dev/null 2>&1
	rlRun "modprobe scsi_debug virtual_gb=128 delay=0"
	sleep 4
	multipath -F > /dev/null 2>&1
	sleep 3
	device=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename`
	sg_gb=60
	is_direct=1
	cnt=0

	for engine in libaio sync; do
		for sched in `sed 's/[][]//g' /sys/block/$device/queue/scheduler`; do
			echo $sched > /sys/block/$device/queue/scheduler
			for pattern in randrw; do
				for depth in 1 8; do
#'bs=64k' test is disabled, because of https://bugzilla.redhat.com/show_bug.cgi?id=1953510
					for bsize in 4 16 32; do
						fio_test $device $engine $sched $pattern $is_direct $depth $bsize $sg_gb
						let cnt+=1
					done
				done
			done
		done
	done

	sleep 3
	rlRun "modprobe -r scsi_debug"
	rlLog "### $cnt"
}

function check_log()
{
	rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        run_test
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
