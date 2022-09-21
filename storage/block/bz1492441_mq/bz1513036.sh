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

	COUNT=16
	RUNTIME=120
	JOBS=10
	SCSI_DBG_NDELAY=10000

# set higher aio limit
	echo 524288 > /proc/sys/fs/aio-max-nr

#figure out the CAN_QUEUE
	CAN_QUEUE=$((($COUNT + 1) * ($COUNT / 2) / 2))
	rmmod scsi_debug -f
	sleep 1
	modprobe scsi_debug virtual_gb=128 max_luns=$COUNT  max_queue=$CAN_QUEUE

# figure out scsi_debug disks
	HOSTS=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*`
	HOSTNAME=`basename $HOSTS`
	HOST=`echo $HOSTNAME | grep -o -E '[0-9]+'`
	DISKS=`lsscsi | grep "\[$HOST\:" | awk '{print $NF}'`

	MY_CAN_QUEUE=`cat /sys/class/scsi_host/$HOSTNAME/can_queue`
	rlLog "host: $HOSTNAME, can_queue: $MY_CAN_QUEUE"

	USE_MQ=`cat /sys/module/scsi_mod/parameters/use_blk_mq`
	if [ $USE_MQ = "Y" ]; then
		SCHEDS=("none" "mq-deadline" "kyber")
	else
		SCHEDS=("noop" "deadline" "cfq")
	fi

	SCHEDS_NR=3
	FIO_JOBS=""
	cnt=0

	for SD in $DISKS; do
		[ $SD = "-" ] && continue
		cnt=$((cnt+1))
		FIO_JOBS=$FIO_JOBS" --name=job1 --filename=$SD: "
		DEV_NAME=`basename $SD`
		Q_PATH=/sys/block/$DEV_NAME/queue

		sched_idx=$(($cnt % $SCHEDS_NR))
		echo ${SCHEDS[$sched_idx]} > $Q_PATH/scheduler
#echo "$cnt +++++++++++++  $Q_PATH/../device/queue_depth"
		echo $cnt > "$Q_PATH/../device/queue_depth"  > /dev/null 2>&1
#cat "$Q_PATH/../device/queue_depth"

		MY_SCHED=`cat $Q_PATH/scheduler | sed -n 's/.*\[\(.*\)\].*/\1/p'`
		MY_SCSI_QD=`cat $Q_PATH/../device/queue_depth`
		rlLog "Dev. $cnt-$DEV_NAME, SCHED: $MY_SCHED, SCSI QD: $MY_SCSI_QD"
	done

	rlLog "start I/O"
	rlRun "fio --rw=randread --size=4G --direct=1 --ioengine=libaio \
		--iodepth=2048 --numjobs=$JOBS --bs=4k --group_reporting=1 \
		--group_reporting=1 --runtime=$RUNTIME \
		--loops=10000 $FIO_JOBS > /dev/null 2>&1 &"

	rlRun "fio --rw=write --size=4G --direct=1 --ioengine=libaio \
		--iodepth=2048 --numjobs=$JOBS --bs=4k --group_reporting=1 \
		--group_reporting=1 --runtime=$RUNTIME \
		--loops=10000 $FIO_JOBS > /dev/null 2>&1 &"

	DDELAY=$(($RUNTIME / $COUNT))
	for SD in $DISKS; do
		[ $SD = "-" ] && continue
		DEV_NAME=`basename $SD`
		DPATH=/sys/block/$DEV_NAME/device
		echo "delete $SD"
		echo 1 > $DPATH/delete
		sleep $DDELAY
	done

	wait
	rlRun "rmmod scsi_debug -f"
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
