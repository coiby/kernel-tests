#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

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
	#Disable some CPUs
	tok "echo 0 > /sys/devices/system/cpu/cpu1/online"
	tok "echo 0 > /sys/devices/system/cpu/cpu2/online"
	tok "echo 0 > /sys/devices/system/cpu/cpu3/online"

for TEST_DISK in $TEST_DISKS; do
	NVME_DISK=${TEST_DISK:0:7}
	MODEL=$(cat /sys/block/"$NVME_DISK"/device/model)
	if [[ $MODEL =~ "SAMSUNG MZPLJ1T6HBJR-00007" ]]; then
		continue
	fi
	tlog "The testing disk $TEST_DISK model is $MODEL"
	{
	local scheds
	local max_nr
	local nr
	scheds="$(sed 's/[][]//g' /sys/block/"$NVME_DISK"/queue/scheduler)"
	# shellcheck disable=SC2068
	for sched in ${scheds[@]}; do
		tlog "$NVME_DISK: testing $sched"
		tok "echo $sched > /sys/block/$NVME_DISK/queue/scheduler"
		max_nr="$(cat /sys/block/"$NVME_DISK"/queue/nr_requests)"
		for ((nr = 4; nr <= max_nr; nr++)); do
			if [[ "$sched" == "none" && "$nr" == "$max_nr" ]]; then
				continue
			fi
			tok "echo $nr > /sys/block/$NVME_DISK/queue/nr_requests"
		done
	done
	} &
done
	wait
	trun dmesg
	#enable the disabled CPUs
	tok "echo 1 > /sys/devices/system/cpu/cpu1/online"
	tok "echo 1 > /sys/devices/system/cpu/cpu2/online"
	tok "echo 1 > /sys/devices/system/cpu/cpu3/online"
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
