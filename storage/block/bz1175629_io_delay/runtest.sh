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
    mkdir -p /tmp/mnt/
    multipath -F
    sleep 3
    rlRun "dmsetup remove_all"
#ls /dev/sd* > dev_txt

    rlRun "lsblk"
    > dev_txt
    dev=$(lsblk |grep part | awk '{print $1}' |egrep -o [a-z0-9]+ | sed ':a ; N;s/\n/ /;ta')
    for i in $(lsblk |grep disk | awk '{print $1}');do
        if [[ $dev =~ $i ]];then
            continue
        else
            echo /dev/$i >> dev_txt
        fi
    done

#echo $devs > dev_txt
    rlRun "cat dev_txt"

    declare -a arr
    declare -a disk_list
    a=`lsblk |grep disk |awk '{print $1}'`
    arr=($a)
    >disk_txt
    for var in "${arr[@]}" ;do
        num=`cat dev_txt |grep "$var"|wc -l`
        if [ $num = 1 ];then
#echo " $var is a disk,have no partition"
            echo "$var" >> disk_txt
        fi
    done
    rlRun "cat disk_txt"
    a=`cat disk_txt`
    arr=($a)
    echo "${#arr[@]}"
    dev="${arr[0]}"
    rlLog "partition"
    parted -s $dev  mklabel gpt  mkpart primary 1M 100G
    partprobe
    rlRun "lsblk"

    if [ `cat /proc/partitions |grep "$arr"|wc -l ` -ge 2 ];then
        sd=`cat /proc/partitions |grep "$arr"|tail -1|awk '{print $4}'`
        device="/dev/$sd"
        echo "from parttion get"
    else 
        device="/dev/$dev"1
        echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    fi

    mkfs.ext4 $device
    rlRun "umount /tmp/mnt/"
    rlRun "mount $device /tmp/mnt"
    rlRun "chrt -r 99 dd if=/dev/zero of=/tmp/mnt/dummy bs=4K count=1 oflag=sync" || trun "dd if=/dev/zero of=/tmp/mnt/dummy bs=4K count=1 oflag=sync"
    echo "do heavy something"
    sh heavy.sh &
    sleep 10
    echo "do heavy"
    echo "please check the time after and before"
    echo "none"
    time dd if=/tmp/mnt/dummy iflag=direct

    echo "deadline"
    echo deadline > /sys/block/$dev/queue/scheduler
    time dd if=/tmp/mnt/dummy iflag=direct
    sleep 5
    echo "cfg"
    echo cfq > /sys/block/$dev/queue/scheduler
    time dd if=/tmp/mnt/dummy iflag=direct
    sleep 5

    he=`ps -ef |grep "heavy" | grep -v "grep" | awk '{print $2}'`
    echo "$? $he"
    for i in "${he[@]}" ; do
        kill -9 "$i"
    done
    echo "$? kill heavy"

    dd_if=`ps -ef |grep "dd if" |grep -v "grep" |awk '{print $2}'`
    echo "$? ${dd_if[*]}"
    for i in "${dd_if[@]}" ; do
        kill -9 "$i"
    done
    echo "$? kill dd if"
    sleep 2

    rlRun "umount $device "
    if [ $? != 0 ];then
        echo "kill all"
        kill -9 "$$" 
        killall dd
        umount $device
    fi

    rm -rf /tmp/*
    parted -s /dev/$dev rm 1
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
