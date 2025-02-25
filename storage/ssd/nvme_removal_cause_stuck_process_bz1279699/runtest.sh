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

for TEST_DISK in $TEST_DISKS; do
	#FIO testing
	trun "dmesg -c &>/dev/null"
	{
	tnot "fio -filename=/dev/${TEST_DISK} -iodepth=1 -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=1200 -time_based -size=1G -group_reporting -name=mytest -numjobs=60" &

	nvme_pci_id="$(get_nvme_pci_id "${TEST_DISK:0:7}")"
	tlog "$TEST_DISK's pci id: $nvme_pci_id"
	sleep 30
	#Remove operation
	tlog "Delete operation on sysfs /sys/bus/pci/devices/${nvme_pci_id}/remove"
	tok "echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/remove"
	wait
	sleep 10
	dmesg
	trun "ls -l /dev/$TEST_DISK"
	tok "test ! -b /dev/$TEST_DISK"
	if [ ! -b "/dev/$TEST_DISK" ]; then
		tlog "device node /dev/$TEST_DISK removed"
	else
		tlog "device node /dev/$TEST_DISK still exists"
	fi
	} &
	wait
done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
