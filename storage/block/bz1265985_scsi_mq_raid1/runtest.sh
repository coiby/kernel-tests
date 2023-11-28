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
source "$CDIR"/../../../cki_lib/libcki.sh     || exit 1
. /usr/share/beakerlib/beakerlib.sh         || exit 1

function run_test()
{
    declare -a arr
    (>disk_txt)
    (>fsdisk)
    sda=$(lsblk |grep boot |awk '{print $1}' |grep -Eo "[a-z]{3}")
    for i in $(ls /sys/block/ |grep sd );do
        if [ "$i" == "$sda" ];then
            rlLog "skip sda boot disk"
            continue
        fi
        parted -s /dev/${i} rm 1
    done

    for i in `ls /sys/block/ |grep sd ` ;do
        (ls -d /sys/block/${i}/sd*)
        if [ $? != 0 ];then
            echo "this ${i} have no parition,used ${i} to parition"
            echo "${i}" >> disk_txt
            (cat disk_txt ) && echo " add those disk now"
            parted -s /dev/${i}  mklabel gpt  mkpart primary 1M 100G
            partprobe
            rlRun "ls -d /sys/block/${i}/sd*"
            num=$(cat disk_txt|grep sd*|wc -l)
            if [ ${num} == 6 ];then
                rlLog "have 6 disks you can used"
                break
            else
                rlLog "have no 6 disks now"
                continue
            fi
        else
            rlLog "${i} disk have parition,not used it "
            continue
        fi
    done

    arry=`cat disk_txt`
    arr=(${arry})
    echo "leng:${#arr[@]}  ${arr[*]}  "

    part
    sleep 1
    partprobe
    sleep 10
    echo "run  stress"
    arry=`cat fsdisk`
    list=(${arry})
    echo "fs disk ${list[*]}"
    echo "fs disk sum  ${#list[@]}"
    if [ ${#list[@]} -lt 4 ];then
        rlLog "fs disk less then 4,so exit"
        part_rm
        exit 1
    else
        rlLog "fs disk more than 4,so select 4 disk to reate raid1"
        sdb=`echo ${arr[0]}`
        sdc=`echo ${arr[1]}`
        sdd=`echo ${arr[2]}`
        sde=`echo ${arr[3]}`
        echo "/dev/${sdb}1 /dev/${sdc}1 /dev/${sdd}1 /dev/${sde}1"
    fi
    test_raid
    sleep 5
    part_rm
}

function part_rm()
{
    for i in "${arr[@]}";do
        echo "remove partition 1 from $i"
        parted -s /dev/${i} rm 1
    done
    rlRun "lsblk"
}

#sdb=`echo ${arr[0]}`
#sdc=`echo ${arr[1]}`
#sdd=`echo ${arr[2]}`
#sde=`echo ${arr[3]}`
#sdf=`echo ${arr[4]}`
#sdg=`echo ${arr[5]}`
#echo "$sdb $sdc $sdd $sde $sdf $sdg"

#list=`echo  ${arr[*]::4}`
#echo "${list} arr   "

function part()
{
    for i in "${arr[@]}";do
        partprobe
        lsblk |grep "${i}1"
        if [ $? != 0 ];then
            rlLog "don't have the partition from lsblk"
            continue
        fi
        sleep 10
        lsblk
        (which mkfs.xfs) && FS="xfs -f" || FS="ext4"
        rlRun "mkfs -t ${FS} /dev/${i}1"
        if [ $? == 0 ];then
            echo "${i} make fs ok now and you can used it to reate raid1"
            echo "${i}"  >>fsdisk;cat fsdisk
        else
            rlLog "don't used ${i} create raid1"
        fi
        sleep 5
        echo "fdisk partition"
    done
}

function test_raid()
{
    num=0
    while [ ${num} -lt 30 ]; do
        echo "*****************************************************$num"
        pvcreate -y /dev/{"$sdb"1,"$sdc"1,"$sdd"1,"$sde"1}
# vgcreate -f black_bird  /dev/{"$sdb"1,"$sdc"1,"$sdd"1,"$sde"1}
        vgcreate  black_bird  /dev/{"$sdb"1,"$sdc"1,"$sdd"1,"$sde"1}
        sleep 5
        lvcreate --type raid1 -m 3 -n non_synced_primary_raid1_3legs_1 -L 3G black_bird /dev/"$sdb"1:0-2400 /dev/"$sdc"1:0-2400 /dev/"$sdd"1:0-2400 /dev/"$sde"1:0-2400
        sleep 5
        lvcreate --type raid1 -m 3 -n non_synced_primary_raid1_3legs_2 -L 3G black_bird /dev/"$sdb"1:0-2400 /dev/"$sdc"1:0-2400 /dev/"$sdd"1:0-2400 /dev/"$sde"1:0-2400
        sleep 5
        lvcreate --type raid1 -m 3 -n non_synced_primary_raid1_3legs_3 -L 3G black_bird /dev/"$sdb"1:0-2400 /dev/"$sdc"1:0-2400 /dev/"$sdd"1:0-2400 /dev/"$sde"1:0-2400
        sleep 5
        dd if=/dev/zero of=/dev/mapper/black_bird-non_synced_primary_raid1_3legs_1 bs=1M oflag=direct &
        dd if=/dev/zero of=/dev/mapper/black_bird-non_synced_primary_raid1_3legs_2 bs=1M oflag=direct &
        dd if=/dev/zero of=/dev/mapper/black_bird-non_synced_primary_raid1_3legs_3 bs=1M oflag=direct &
        echo offline > /sys/block/"$sdb"/device/state
        sleep 5
        pvs
        sleep 2
        killall dd
        sleep 2
        killall dd
        echo running > /sys/block/"$sdb"/device/state
        lvremove -y /dev/black_bird/non_synced_primary_raid1_3legs_1
        lvremove -y /dev/black_bird/non_synced_primary_raid1_3legs_2
        lvremove -y /dev/black_bird/non_synced_primary_raid1_3legs_3
        (vgremove black_bird) || (vgremove -f black_bird)
        pvremove /dev/{"$sdb"1,"$sdc"1,"$sdd"1,"$sde"1}
        sleep 5
        echo "${num} time finished raid1_leg test"
        ((num++))
    done
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
