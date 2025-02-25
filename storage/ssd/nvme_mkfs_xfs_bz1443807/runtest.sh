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

	install_iozone
	for FS in ext4 xfs; do
		for TEST_DISK in $TEST_DISKS; do

			# variable definitions
			local mountP="/mnt/fortest/$TEST_DISK"
			local process_num=6
			local file_parameter="${mountP}/iozone0.tmp ${mountP}/iozone1.tmp ${mountP}/iozone2.tmp ${mountP}/iozone3.tmp ${mountP}/iozone4.tmp ${mountP}/iozone5.tmp"
			local default_parameter="-t $process_num -F $file_parameter"

			tlog "INFO: Executing Iozone_6_Process_Test() with device: ${TEST_DISK}"

			#make file system on nvme disk
			if [ $FS = "ext4" ]; then
				tok "mkfs.$FS -F /dev/${TEST_DISK}"
			elif [ $FS = "xfs" ]; then
				tok "mkfs.$FS -f /dev/${TEST_DISK}"
			fi
			if [ ! -d "$mountP" ]; then
				mkdir -p "$mountP"
			fi

			{
			trun "mount /dev/$TEST_DISK $mountP"
			tlog "Executing iozone testing for ${TEST_DISK} on mountP:$mountP"
			tok "iozone $default_parameter -s 102400M -r 1M -i 0 -i 1 -+d -+n -+u -x -e -w -C"
			if [ $? -ne 0 ]; then
				tlog "FAIL: iozone testing for ${TEST_DISK} failed"
			fi
			tok "umount -l /dev/${TEST_DISK}"
			rm -fr "$mountP"
			} &
		done
		wait
	done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
