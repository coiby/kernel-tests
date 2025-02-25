#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	get_nvme_disk

for DISK in $DISKS; do
	nvme_char=${DISK:0:5}

	#Reset_controller operation
	{
	tlog "Will do reset_controller operation from /sys/class/nvme/$nvme_char/reset_controller"
	tok "echo 1 > /sys/class/nvme/$nvme_char/reset_controller"
	sleep 5
	tlog "check whether NVMe disk still can be used after reset_controller"
	tok "dd if=/dev/$DISK of=/dev/null bs=1M count=1024"
	if [ $? -ne 0 ]; then
		tlog "dd read operation failed on $DISK"
		dmesg
	fi
	tok "dd if=/dev/zero of=/dev/$DISK bs=1M count=1024"
	if [ $? -ne 0 ]; then
		tlog "dd write operation failed on $DISK"
		dmesg
	fi
	} &
done
	wait
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
