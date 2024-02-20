#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	install_fio

	get_nvme_disk

	partition_1_primary "$DISKS"

	trun "dmesg -c &>/dev/null"

for TEST_DISK in $TEST_DISKS; do

	#FIO testing
	tok "fio -filename=/dev/${TEST_DISK} -iodepth=1 -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=1200 -time_based -size=1G -group_reporting -name=mytest -numjobs=60" &
done
	sleep 10
	STATE=0
	j=1
	MAXCPUs=$(nproc)
	((MAXCPUs--))
	MINCPU=1
	while((j <= 10))
	do
		for i in $(seq "$MINCPU" "$MAXCPUs")
		do
			if ((i%4)); then
				tok "echo $STATE > /sys/devices/system/cpu/cpu$i/online"
			fi
		done
		if [[ $STATE -eq 1 ]]; then
			STATE=0
		else
			STATE=1
		fi
		((j++))
	done

	for k in $(seq "$MINCPU" "$MAXCPUs")
	do
		tok "echo 1 > /sys/devices/system/cpu/cpu$k/online"
	done

	wait
	trun dmesg
}

tlog "running $0"
trun "uname -a"
runtest
tend
