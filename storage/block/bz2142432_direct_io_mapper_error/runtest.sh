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

function get_disk()
{
    disk_list=()
    echo "will get disk to create raid container and raid "
    for i in $(ls /dev/sd? |awk -F / '{print $3}');do
        n=$(cat /proc/partitions  |awk '{print $4}' |egrep $i |wc -l)
        if [ $n = 1 ];then
            echo "$i have no partition"
            disk_list+=( $i)
        fi
    done

    echo "free device:" "${disk_list[@]}"
    for i in $(seq 0 ${#disk_list[@]});do
        eval "dev$i=${disk_list[$i]}"
    done
}

function run_test()
{
# find local free disk
    get_disk
    # shellcheck disable=SC2154
    rlRun "parted -s /dev/$dev0 mklabel gpt mkpart xfs 1M 50G"
    # shellcheck disable=SC2154
    rlRun "parted -s /dev/$dev1 mklabel gpt mkpart xfs 1M 50G"
    rlRun "echo bfq > /sys/block/$dev0/queue/scheduler"
    rlRun "echo bfq > /sys/block/$dev1/queue/scheduler"

# disk0=/dev/"$dev0"1
# disk1=/dev/"$dev1"1
    passwd="123@redhat##"
    rlRun 'echo $passwd | cryptsetup luksFormat --sector-size 4096 /dev/"$dev0"1'
    rlRun 'echo $passwd | cryptsetup luksFormat --sector-size 4096 /dev/"$dev1"1'
# cryptsetup passwd 123@redhat##
    rlRun "lsblk"

    rlRun 'echo $passwd | cryptsetup luksOpen /dev/"$dev0"1 raid1'
    rlRun 'echo $passwd | cryptsetup luksOpen /dev/"$dev1"1 raid2'
    rlRun "lsblk"

    rlRun "mdadm --create --level=1 --metadata=1.2 --raid-devices=2 /dev/md0 /dev/mapper/raid1 /dev/mapper/raid2"
    rlRun "cat /proc/mdstat"
# wait md raid sync done
    cmd3=$(cat /proc/mdstat | grep resync)
    while [ -n "$cmd3" ];do
        sleep 60
        cmd3=$(cat /proc/mdstat | grep resync)
    done
    rlRun "cat /proc/mdstat"
    rlRun "pvcreate /dev/md0"
    rlRun "vgcreate lvmraid /dev/md0"
    rlRun "lvcreate -n wrk -L 20G lvmraid"
    rlRun "lsblk"
    rlRun "lsblk -t -a"

    rlRun "gcc -O2 -pthread test.c"
    for i in $(seq 1 64); do ./a.out;done
    wait
}

function clean_up()
{
    rlRun "lvremove /dev/lvmraid/wrk -f"
    rlRun "vgremove lvmraid"
    rlRun "pvremove /dev/md0"

    rlRun "mdadm -S /dev/md0"
    rlRun "mdadm --zero-superblock /dev/mapper/raid1"
    rlRun "mdadm --zero-superblock /dev/mapper/raid2"

    rlRun "cryptsetup luksClose raid1"
    rlRun "cryptsetup luksClose raid2"

    rlRun "lsblk"

# remove partitions
    rlRun "parted -s /dev/$dev0 rm 1"
    rlRun "parted -s /dev/$dev1 rm 1"

    rlRun "dd if=/dev/zero of=/dev/$dev0 bs=1M count=1"
    rlRun "dd if=/dev/zero of=/dev/$dev1 bs=1M count=1"

    rlRun "lsblk"
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
        run_test
        clean_up
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
