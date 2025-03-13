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

	partition_1_primary "$DISKS"

for TEST_DISK in $TEST_DISKS; do

	local mountP="/mnt/fortest/$TEST_DISK"
	[ ! -d "$mountP" ] && mkdir -p "$mountP"

	#make file system on nvme disk
	tok mkfs.xfs -f "/dev/$TEST_DISK"

	#create directory to mount partition on nvme disk
	tok mount "/dev/$TEST_DISK" "$mountP"

	{
	tok "dd if=/dev/zero of=$mountP/testfile bs=1M count=512000 conv=fdatasync"
	tok "rm -f $mountP/testfile"

	#umount disk partition
	tok "umount /dev/$TEST_DISK"
	tok "rm -fr $mountP"
	} &
done
	wait
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
