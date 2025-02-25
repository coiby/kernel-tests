#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	install_fio

	get_nvme_disk

	partition_1_primary "$DISKS"

for DISK in $DISKS; do

	MODEL=$(cat /sys/block/"$DISK"/device/model)
	tlog "The testing disk $DISK model is $MODEL"

	#BZ2097317
	if [[ $MODEL =~ "INTEL SSDPEDMD016T4" ]]; then
		continue
	fi

	#FIO testing
	dmesg -c
	{
	tnot "fio -filename=/dev/${DISK}p1 -iodepth=1 -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=1200 -time_based -size=1G -group_reporting -name=mytest -numjobs=60" &
	sleep 5

	nvme_pci_id="$(get_nvme_pci_id "$DISK")"

	local int=1
	while((int < 11))
	do
		tlog "INFO: echo 1 > /sys/bus/pci/rescan"
		tok "echo 1 > /sys/bus/pci/rescan"
		sleep 3
		#Remove operation
		tlog "INFO: echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/rescan"
		tok "echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/rescan"
		tlog "INFO: echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/reset"
		tok "echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/reset"
		tlog "INFO: echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/remove"
		tok "echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/remove"
		((int++))
	done
	wait
	dmesg
	tok "test ! -b /dev/{$DISK}p1"
	if [ ! -b "/dev/${DISK}p1" ]; then
		tlog "INFO: device node /dev/${DISK}p1 removed"
	else
		tlog "FAIL: device node /dev/${DISK}p1 still exists"
		return 1
	fi
	} &
	wait
done
	tlog "INFO: echo 1 > /sys/bus/pci/rescan"
	tok "echo 1 > /sys/bus/pci/rescan"
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
