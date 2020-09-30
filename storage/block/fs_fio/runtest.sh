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
source $CDIR/../../../cki_lib/libcki.sh || exit 1

function run_test()
{
        rmmod scsi_debug > /dev/null 2>&1
        rlRun "modprobe scsi_debug dev_size_mb=6144"
        sleep 4
        multipath -F > /dev/null 2>&1
        sleep 3

# figure out scsi_debug disks
        HOSTS=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*`
        HOSTNAME=`basename $HOSTS`
        DISK=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename`
        DEV=/dev/$DISK
        MNT=/mnt/test
        [ ! -d $MNT ] && mkdir $MNT

        for sched in `sed 's/[][]//g' /sys/block/$DISK/queue/scheduler`; do
                echo $sched > /sys/block/$DISK/queue/scheduler
                for fstype in ext2 ext3 ext4 xfs; do
                        fio_test $HOSTNAME $DEV $sched $fstype $MNT
                done
        done

        sleep 3
        rlRun "modprobe -r scsi_debug"
}

function fio_test()
{
        host=$1
        device=$2
        sched=$3
        fstype=$4
        mnt=$5

        echo "HOST:$host ,DISK:$device ,I/O SCHED:$sched ,FSTYPE:$fstype" | tee /dev/kmsg
        if [[ $fstype == "xfs" ]];then
                mkfs -t $fstype -f $device
        else
                mkfs -t $fstype -F $device
        fi
        mount $device $mnt

        rlRun "fio --size=2048m --bsrange=512-8k --numjobs=2 --runtime=60 \
                --ioengine=libaio --iodepth=32 --directory=$mnt --group_reporting=1 \
                --unlink=0 --direct=1 --fsync=0 --name=f1 --stonewall --rw=write &> /dev/null"

        wait
        rm -rf $mnt/*
        umount $mnt
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
