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

# TEST is required for beakerlib tests
TEST=${RSTRNT_TASKNAME}

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh || exit 1

function restore_swap()
{
        rlRun "modprobe -v zram"
        rlRun "echo zstd > /sys/block/zram0/comp_algorithm"
        rlRun "echo 4G > /sys/block/zram0/disksize"
        rlRun "mkswap /dev/zram0"
        rlRun "swapon /dev/zram0"
        rlRun "lsblk"
}

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

### create one zram device
        rlRun "modprobe zram num_devices=1"
        sleep 3

### check and set zstd compression
        rlRun "cat /sys/block/zram0/comp_algorithm"
        rlRun "echo zstd > /sys/block/zram0/comp_algorithm"
        rlRun "cat /sys/block/zram0/comp_algorithm"
### < *** the output must contain "[zstd]" here *** >

### set max ram usage = 1GB
        rlRun "echo 1G > /sys/block/zram0/disksize"
        rlRun "lsblk"

### write, read and test some data (/boot, for example)
        rlRun "mke2fs -m 0 -b 4096 -O sparse_super -L zram /dev/zram0"
        [ ! -d /mnt/zram ] && rlRun "mkdir -p /mnt/zram"
        rlRun "mount -o relatime,noexec,nosuid /dev/zram0 /mnt/zram"
        rlRun "mount | grep zram"
        rlRun "lsblk"

        [[ -d temp ]] || mkdir temp
        for i in $(seq 1 10);do
            dd if=/dev/urandom of=temp/test.file$i count=10 bs=1M iflag=fullblock
        done

        rlRun "ls temp"
        rlRun "cp -r temp /mnt/zram"
        rlRun "umount /mnt/zram"
        rlRun "echo 3 > /proc/sys/vm/drop_caches"

        rlRun "mount -o relatime,noexec,nosuid /dev/zram0 /mnt/zram"
        rlRun "diff -rp temp /mnt/zram/temp"
### < *** must be no output here *** >

### get funny stats
        rlLog "get funny stats"
        awk '{ print "uncompressed size of data",$1 }' /sys/block/zram0/mm_stat
        awk '{ print "compressed size of data", $2 }' /sys/block/zram0/mm_stat
        awk '{ print "memory allocated for this disk",$3 }'  /sys/block/zram0/mm_stat
        awk '{ print "number of incompressible pages", $8 }' /sys/block/zram0/mm_stat

### uncreate
        rlRun "umount /mnt/zram"
        rlRun "rm -rf /mnt/zram/*"
        rlRun "rmdir /mnt/zram/"
        rlRun "rmmod zram"
        rlRun "rm -rf temp"
        [[ -z $swap_size ]] || restore_swap
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
        rlRun "rpm -q zstd rsync || yum install -y zstd rsync"
        run_test
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
