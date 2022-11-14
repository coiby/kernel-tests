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
source $CDIR/../../../cki_lib/libcki.sh         || exit 1
. /usr/share/beakerlib/beakerlib.sh             || exit 1

function run_test()
{
    for i in $(ls /dev/sd? |awk -F / '{print $3}');do
        n=$(cat /proc/partitions  |awk '{print $4}' |egrep $i |wc -l)
        if [ $n = 1 ];then
            rlLog "$i have no partition"
            disk=$i
            break
        fi
    done

    rlRun 'echo "+cpuset +cpu +io" > /sys/fs/cgroup/cgroup.subtree_control'
    rlRun "cat /sys/fs/cgroup/cgroup.subtree_control"
    rlRun "mkdir /sys/fs/cgroup/test"
    rlRun "cat /sys/fs/cgroup/test/cgroup.controllers"

    rlRun "ls -l /dev/$disk"
    MAJ=$(ls -l /dev/$disk | awk -F ',' '{print $1}' | awk -F ' ' '{print $NF}')
    MIN=$(ls -l /dev/$disk | awk -F ',' '{print $2}' | awk -F ' ' '{print $1}')

    rlRun 'echo "$MAJ:$MIN wbps=1024" > /sys/fs/cgroup/test/io.max'
    rlRun "cat /sys/fs/cgroup/test/io.max"

    rlRun 'date +"%M:%S"'
    begin=$(date +"%s")
    rlRun "echo $$ > /sys/fs/cgroup/test/cgroup.procs"
    rlRun "dd if=/dev/zero of=/dev/$disk bs=10k count=1 oflag=direct &"
    rlRun "dd if=/dev/zero of=/dev/$disk bs=10k count=1 oflag=direct &"
    wait
    rlRun 'date +"%M:%S"'
    end=$(date +"%s")

    result=$(expr $end - $begin)
    rlLog "Result: $result"
    [[ $result -lt 20 ]] && rlFail "test fail,please check"

    rm -rf /sys/fs/cgroup/test
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
