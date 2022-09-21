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

function IO_flag()
{
	echo "partition $dev 1 2 3 5 ,5 is logic"
	partprobe
	sda1="$dev"1
	sda2="$dev"2
	sda5="$dev"5
	echo "$sda1 $sda2 $sda5"
	rm -rf /tmp/stoptest
#while [ ! -f /tmp/stoptest ]; do
#      trun " dd if=$sda1 of=/dev/null bs=512c count=1 iflag=direct >/dev/null 2>&1"
#        trun "cat /proc/diskstats |grep "$device"1 >> sda1.txt"
#done &

#while [ ! -f /tmp/stoptest ]; do
#        trun "dd if=$sda2 of=/dev/null bs=512c count=1 iflag=direct >/dev/null 2>&1"
#        trun "cat /proc/diskstats |grep "$device"2 >> sda2.txt"
#done &

#while [ ! -f /tmp/stoptest ]; do
#        trun "dd if=$sda5 of=/dev/null bs=512c skip=128 count=1 iflag=direct >/dev/null 2>&1"
#        trun "cat /proc/diskstats |grep "$device"5 >> sda5.txt"
#done &

	rlRun "gcc -D _GNU_SOURCE -o readdisk read.c"
	BLK1=`cat /sys/block/"$device"/"$device"1/start`
	rlLog "read 512b from $BLK1"
	./readdisk $BLK1 $dev &
	pid1=$$
	./readdisk $(($BLK1 - 1 )) $dev &
	pid2=$$
#cat /proc/diskstats | grep sda | awk '{print $3,$(NF-2);}'
	rlRun "cat /proc/diskstats |grep "$device"1 >> sda1.txt"

	BLK2=`cat /sys/block/"$device"/"$device"2/start`
	rlLog "read 512b from $BLK2"
	./readdisk $BLK2 $dev &
	pid3=$$
	./readdisk $(($BLK2 - 1 )) $dev &
	pid4=$$
#cat /proc/diskstats | grep sda | awk '{print $3,$(NF-2);}'
	rlRun "cat /proc/diskstats |grep "$device"2 >> sda2.txt"

	BLK5=`cat /sys/block/"$device"/"$device"5/start`
	rlLog "read 512b from $BLK5"
	./readdisk $BLK5 $dev &
	pid5=$$
	./readdisk $(($BLK5 - 1 )) $dev &
	pid6=$$
#cat /proc/diskstats | grep sda | awk '{print $3,$(NF-2);}'
	rlRun "cat /proc/diskstats |grep "$device"5 >> sda5.txt"

	while [ ! -f /tmp/stoptest ]; do
		(cat /proc/diskstats |grep "$device" >> sda.txt) >/dev/null 2>&1
		(cat /proc/diskstats |grep "$device"1 >> sda1.txt) >/dev/null 2>&1
		(cat /proc/diskstats |grep "$device"2 >> sda2.txt) >/dev/null 2>&1
		(cat /proc/diskstats |grep "$device"5 >> sda5.txt) >/dev/null 2>&1
	done &
}

function data_check()
{
#tok "cat sda1.txt |grep "$device"1 |awk '{ if ( $12 >0 && $12 < 4 ) {print $12 }}' >>/var/log/sda1_IO.txt"
#tok "cat sda2.txt |grep "$device"2 |awk '{ if ( $12 >0 && $12 < 4 ) {print $12 }}' >>/var/log/sda2_IO.txt"
#tok "cat sda5.txt |grep "$device"5 |awk '{ if ( $12 >0 && $12 < 5 ) {print $12 }}' >>/var/log/sda5_IO.txt"
	cat sda1.txt |grep "$device"1 |awk '{ if ( $12 >0 && $12 < 10 ) {print $12 }}' |sort|uniq >>/var/log/sda1_IO.txt
	cat sda2.txt |grep "$device"2 |awk '{ if ( $12 >0 && $12 < 10 ) {print $12 }}'|sort|uniq >>/var/log/sda2_IO.txt
	cat sda5.txt |grep "$device"5 |awk '{ if ( $12 >0 && $12 < 10 ) {print $12 }}'|sort|uniq >>/var/log/sda5_IO.txt
	cat sda.txt |grep "$device" |awk '{ if ( $12 >0 && $12 < 10 ) {print $12 }}'|sort|uniq >>/var/log/sda_IO.txt
	cat sda.txt |grep "$device" |awk '{print $12}' |sort|uniq >>sum.txt
	cat sda1.txt |grep "$device"1 |awk '{print $12}' |sort|uniq >>sum.txt
	cat sda2.txt |grep "$device"2 |awk '{print $12}' |sort|uniq >>sum.txt
	cat sda5.txt |grep "$device"5 |awk '{print $12}' |sort|uniq >>sum.txt
	rlRun "cat sum.txt|sort|uniq"
	for i in `cat sum.txt|sort|uniq`;do
		echo $i
		if [[ "$i" -lt "20" ]];then
			echo "the io $i sum was in the range"
			if [[ $i -ge 1 ]];then
				echo "more than 1 and passed"
			else
				echo "this $i no moro than 1 failed"
				if [ $i = 0 ];then
					echo " this one was 0,continue"
					continue
				fi
				remove_disk
				exit 1
			fi
		else
			echo "the io $i sum was not in range"
		fi
	done
	(echo "on sda")
	(cat /var/log/sda_IO.txt|sort|uniq) && (echo "on sda")
	(echo "on sda1")
	(cat /var/log/sda1_IO.txt|sort|uniq) && (echo "on sda1")
	(echo "on sda2")
	(cat /var/log/sda2_IO.txt|sort|uniq) && (echo "on sda2")
	(echo "on sda5")
	(cat /var/log/sda5_IO.txt|sort|uniq) && (echo "on sda5")
}

function remove_disk()
{
	echo "rm parttition"
	lsblk
	fdisk $dev << EOF
d
5
d
3
d
2
d

w
EOF
	partprobe
	lsblk
}

function runtest()
{
	rlRun "mv read.txt read.c"
	cat /proc/scsi/scsi
	ls /dev/sd* > dev_txt
	declare -a arr
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
	a=`cat disk_txt`
	arr=($a)
	echo "have ${#arr[@]} HDD don't partition"
	dev=/dev/"${arr[0]}"
	device=${arr[0]}
	echo "$dev $device"

	fdisk $dev <<EOF
n
p
1

+10G
n
p
2

+20G
n
e
3

+30G
n
l
5


w
EOF
	lsblk

	(>sda1.txt)
	(>sda2.txt)
	(>sda5.txt)
	(>sda.txt)

	rlLog "do IO_flag function"
	IO_flag
	sleep 20

	(>/var/log/sda1_IO.txt)
	(>/var/log/sda2_IO.txt)
	(>/var/log/sda5_IO.txt)
	(>sum.txt)
	mkdir -p /tmp/
	touch /tmp/stoptest && echo "stop test"
	(killall readdisk)
	data_check
#>/var/log/sda1_IO.txt
#>/var/log/sda2_IO.txt
#>/var/log/sda5_IO.txt
	lsblk
	rlLog "remove disk now "
	remove_disk
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
