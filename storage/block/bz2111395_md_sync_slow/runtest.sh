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
source $CDIR/../../../cki_lib/libcki.sh		|| exit 1
. /usr/share/beakerlib/beakerlib.sh			|| exit 1

function get_disk()
{
	disk_list=()
	echo "will get disk to create raid container and raid "
	for i in $(ls /dev/sd? |awk -F / '{print $3}');do
		n=$(cat /proc/partitions  |awk '{print $4}' |egrep $i |wc -l)
		if [ $n = 1 ];then
			echo "$i have no partition"
			disk_list+=( /dev/$i)
		fi
	done

	rlLog "free device: ${disk_list[*]}"
	for i in $(seq 0 ${#disk_list[@]});do
		eval "dev$i=${disk_list[$i]}"
	done
}

function run_test()
{
	get_disk
	# shellcheck disable=SC2154
	rlRun "mdadm -CR -v /dev/md5 -l 5 -n 6 $dev0 $dev1 $dev2 $dev3 $dev4 $dev5"
	sleep 60
	rlRun "cat /proc/mdstat"
	for i in $(seq 0 5);do
		rlRun "hdparm -t /dev/md5"
		sleep 60
	done
	p=$(hdparm -t /dev/md5 | awk -F ' ' '{print $11}' | awk -F '.' '{print $1}')
	if [[ "$p" -gt "500" ]];then
		rlLog "PASS"
	else
		rlLog "FAILED"
		exit 1
	fi

	cat /proc/mdstat | grep recovery
	while [ $? -eq 0 ];do
		rlLog "recovery not yet completed"
		sleep 300
		cat /proc/mdstat | grep recovery
	done

	rlRun "fio --filename=/dev/md5 --ioengine=libaio --prio=0 \
		--numjobs=32 --direct=1 --iodepth=1 --fadvise_hint=0 \
		--runtime=30 --ramp_time=10 --bwavgtime=5000 --time_based \
		--norandommap --rw=write --bs=128k --group_reporting \
		--name=/dev/rootvg/test --size=10g"

	rlRun "mdadm -S /dev/md5"
	rlRun "mdadm --zero-superblock $dev0"
	rlRun "mdadm --zero-superblock $dev1"
	rlRun "mdadm --zero-superblock $dev2"
	rlRun "mdadm --zero-superblock $dev3"
	rlRun "mdadm --zero-superblock $dev4"
	rlRun "mdadm --zero-superblock $dev5"
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
