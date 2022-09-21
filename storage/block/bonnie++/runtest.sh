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
    rlRun " dmsetup remove_all"
    rlRun "lsblk"
#ls /dev/sd* > dev_txt

    > dev_txt
    dev=$(lsblk |grep part | awk '{print $1}' |egrep -o [a-z0-9]+ | sed ':a ; N;s/\n/ /;ta')
    for i in $(lsblk |grep disk | awk '{print $1}');do
        if [[ $dev =~ $i ]];then
            continue
        else
            echo /dev/$i >> dev_txt
        fi
    done

    rlRun "cat dev_txt"

    declare -a arr
    declare -a disk_list
    a=`lsblk |grep disk |awk '{print $1}'`
    arr=($a)
    >disk_txt
    for var in $(${arr[*]});do
        num=`cat dev_txt |grep "$var"|wc -l`
        if [ $num = 1 ];then
#echo " $var is a disk,have no partition"
            echo "$var" >> disk_txt
        fi
    done
    rlRun "cat disk_txt"
    a=`cat disk_txt`
    arr=($a)
    echo "${#arr[@]},HDD don't partition"
    dev=/dev/"${arr[0]}"
    hd="${arr[0]}"
    rlLog "partition"
    parted -s $dev  mklabel gpt  mkpart primary 1M 100G
    partprobe
    rlRun "lsblk"
    sd=`cat /proc/partitions |grep "$arr"|tail -1|awk '{print $4}'`
    device="/dev/$sd"
    which mkfs.xfs
    if [ $? -eq 0 ]; then
        FILESYS="xfs -f "
    else
        which mkfs.ext4
        if [ $? -eq 0 ]; then
            FILESYS="ext4"
        else
            FILESYS="ext3"
        fi
    fi

    rlRun " mkfs -t $FILESYS $device"
    if [ $? -ne 0 ]; then
        rlLog "Create $FILESYS on $device failed"
        return 1
    fi

    rlRun " mount $device /tmp/mnt"

    echo "######################################################################"

    if [ "$TEST_PARAM_MEM_MULT" == "" ];then
        echo "using default setting for Memory Multiplier"
        MEM_MULT=2
    else
        MEM_MULT="$TEST_PARAM_MEM_MULT"
    fi

    FULLMEM=`grep MemTotal /proc/meminfo | awk '{ print $2}'`
    MEMORY=`echo "2 k ${FULLMEM} 1024 / f" | dc | awk '{ printf "%d", $1 }'`;
    #File size should be 2x (or more) the size of memory
    FSIZE=$(expr $MEM_MULT \* $MEMORY)
    echo "$FSIZE"
    BONNIE_CMD="-u root -s $FSIZE  -d /tmp/mnt"
    echo "$BONNIE_CMD"
    wget http://www.coker.com.au/bonnie++/bonnie++-1.03e.tgz
    tar -zxvf bonnie++-1.03e.tgz

# First we need to make bonnie++
# switch to the tiobench directory for all runs
    cd bonnie++-1.03e
    if [ $? = 0 ];then
        make -f Makefile clean >/dev/null 2>&1
        status=$?
        if [ "$status" -ne 0 ]; then
            exit $status
        fi
        make -f Makefile  > /dev/null 2>&1
        status=$?
        if [ "$status" -ne 0 ]; then
            exit $status
        fi
    fi
# Run the actual test and redirect the output to the log file,
# so if need be we will have the debug info after the fact.

    printf 'Starting bonnie++\n'
    rlLog "The bonnie command line is $BONNIE_CMD"
    ./bonnie++ $BONNIE_CMD > out.txt
    status=$?

    if [ $status -eq 0 ]; then
        result=PASS
    else
        rlLog "bonnie++ failed - status =$status" | tee -a out.txt
        result=FAIL
    fi

# Then file the results in the database
    rlLog "-----bonnie++ complete----- Result = $result" | tee -a out.txt

    rlRun "cat out.txt"
    umount "$device"
    parted -s $dev rm 1
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
