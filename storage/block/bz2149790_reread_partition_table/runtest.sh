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

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

# Include enviroment and libraries
# shellcheck source=/dev/null
source "$CDIR"/../../../cki_lib/libcki.sh || exit 1

function get_disk()
{
    disk_list=()
    echo "will get disk to create raid container and raid "
    for i in $(ls /dev/sd? |awk -F / '{print $3}');do
        n=$(cat /proc/partitions  |awk '{print $4}' | egrep "$i" |wc -l)
        if [ "$n" = 1 ];then
            echo "$i have no partition"
            disk_list+=( "$i")
        fi
    done

    echo "free device:" "${disk_list[@]}"
    for i in $(seq 0 ${#disk_list[@]});do
        eval "dev$i=${disk_list[$i]}"
    done
}

function setup_md()
{
    get_disk
    # shellcheck disable=SC2154
    rlLog "disk: $dev0 $dev1"
    wipefs -a /dev/${dev0}
    wipefs -a /dev/${dev1}
    rlRun 'mdadm -CR /dev/md0 -l 1 -n 2 /dev/"$dev0" /dev/"$dev1" -e 1.0'
    md_result=$?
    if [ ${md_result} != 0 ];then
        rlRun "lsblk"
        rstrnt-report-result "md raid create faied!" FAIL 1
        exit 1
    fi
}

function run_test()
{
    setup_md
# gdisk removed from rhel10
    if rlIsRHEL '>=10' ;then
        rlRun "parted -s /dev/md0 mklabel gpt mkpart xfs 1M 100M"
    else
        rlRun "yum install -y gdisk"
        rlRun "sgdisk -n 0:0:+100MiB /dev/md0"
    fi

    rlRun "lsblk"
    rlRun "cat /proc/partitions"
    rlRun "mdadm -S /dev/md0"
    rlRun 'mdadm -A /dev/md0 /dev/"$dev0" /dev/"$dev1"'
    sleep 10
    rlRun "lsblk"
#    rlRun "cat /proc/partitions"
#    rlRun 'cat /proc/partitions | grep "$dev0"1' 1 "reread partition issue"
#    rlRun 'cat /proc/partitions | grep "$dev1"1' 1 "reread partition issue"

    if rlIsRHEL '>=10' ;then
        rlRun "parted -s /dev/md0 rm 1"
    else
        rlRun "sgdisk --zap-all /dev/md0"
    fi

    sleep 10
    rlRun "lsblk"
#    rlRun "cat /proc/partitions"
#    rlRun 'cat /proc/partitions | grep "$dev0"1' 1 "reread partition issue"
#    rlRun 'cat /proc/partitions | grep "$dev1"1' 1 "reread partition issue"
    rlRun "mdadm -S /dev/md0"
    sleep 10
    wait
    rlRun 'mdadm --zero-superblock /dev/"$dev0"'
    rlRun 'mdadm --zero-superblock /dev/"$dev1"'
    while [ -b /dev/md0 ]; do
        sleep 3
    done
    rlRun "wipefs -a /dev/${dev0}"
    rlRun "wipefs -a /dev/${dev1}"
    rlRun "cat /proc/partitions"
    rlRun 'cat /proc/partitions | grep "$dev0"1' 1 "reread partition issue"
    rlRun 'cat /proc/partitions | grep "$dev1"1' 1 "reread partition issue"
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
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
