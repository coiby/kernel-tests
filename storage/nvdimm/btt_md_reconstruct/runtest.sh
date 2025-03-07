#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest() {

	which mkfs.ext4
	if [ $? -eq 0 ]; then
		FILESYS="ext4"
	else
		FILESYS="ext3"
	fi

	sector_size_list="$SECTOR_SIZE_LIST"
	for sector_size in $sector_size_list; do

		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 4 BTT "$sector_size"
		devlist=$RETURN_STR

		for i in 1 4 5 6 10; do

			RETURN_STR=''
			MD_RAID=''
			disk=''
			state=""
			raid_num=4
			bitmap=1
			spare_num=0

			MD_Create_RAID $i "$devlist" $raid_num $bitmap $spare_num
			if [ $? -ne 0 ];then
				tlog "FAIL: Failed to create md raid $RETURN_STR"
				break
			else
				tlog "INFO: Successfully created md raid $RETURN_STR"
			fi
			MD_RAID=$RETURN_STR

			disk=`echo $devlist| cut -d " " -f 1`
			disk="/dev/"$disk
			while [ ! -b $MD_RAID ]; do
				sleep 1
			done

			MD_Get_State_RAID $MD_RAID
			state=$RETURN_STR

			while [[ $state != "active" && $state != "clean" ]]; do
				sleep 5
				MD_Get_State_RAID $MD_RAID
				state=$RETURN_STR
			done
			tlog "mkfs -t $FILESYS $MD_RAID"
			tok mkfs -t $FILESYS $MD_RAID
			if [ ! -d /mnt/md_test ]; then
				mkdir /mnt/md_test
			fi
			tok mount -t $FILESYS $MD_RAID /mnt/md_test
			tok dd if=/dev/urandom of=/mnt/md_test/testfile bs=1M count=100
			md5sum /mnt/md_test/testfile > md5.old

			tlog "mdadm --fail $MD_RAID $disk"
			tok mdadm --fail $MD_RAID $disk
			sleep 5
			tlog "mdadm --remove $MD_RAID $disk"
			tok mdadm --remove $MD_RAID $disk
			sleep 5
			tok mdadm --zero-superblock $disk
			tok mdadm --add $MD_RAID $disk
			if [ $? -ne 0 ]; then
				tlog "FAIL: fail to reconstruct raid"
			fi

			sleep 2
			MD_Get_State_RAID $MD_RAID
			state=$RETURN_STR
			while [[ $state != "active" && $state != "clean" ]]; do
				sleep 5
				MD_Get_State_RAID $MD_RAID
				state=$RETURN_STR
			done

			tok umount $MD_RAID
			tok mount $MD_RAID /mnt/md_test
			md5sum /mnt/md_test/testfile > md5.new
			tok diff md5.new md5.old
			if [ $? -ne 0 ]; then
				tlog "FAIL: md5 checksum changed"
			else
				tlog "md5 checksum successfully"
			fi
			tok umount $MD_RAID

			FIO_Device_Level_Test $MD_RAID
			sleep 5
			MD_Clean_RAID $MD_RAID

		done
	done
	if [ $? -ne 0 ];then
		exit 1
	fi
}

tlog "running $0"
trun "rpm -q mdadm || yum install -y mdadm"
trun "uname -a"
runtest
report_result
tend
