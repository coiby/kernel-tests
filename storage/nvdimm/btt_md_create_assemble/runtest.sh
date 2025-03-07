#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function Stop_Raid (){
	tok mdadm --stop "$MD_RAID"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fail to stop md raid $MD_RAID."
		exit 1
	fi
}

function runtest (){

	devlist=''

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
		RAID_LIST="0 1 4 5 6 10"
		for level in $RAID_LIST; do

			RETURN_STR=''
			MD_RAID=''
			MD_DEV_LIST=''
			raid_num=4
			spare_num=0
			if [ "$level" = "0" ];then
				bitmap=0
			else
				bitmap=1
			fi
			MD_Create_RAID $level "$devlist" $raid_num $bitmap $spare_num
			if [ $? -ne 0 ];then
				tlog "FAIL: Failed to create md raid $RETURN_STR"
				break
			else
				tlog "INFO: Successfully created md raid $RETURN_STR"
			fi
			MD_RAID=$RETURN_STR

			MD_Get_State_RAID $MD_RAID
			state=$RETURN_STR

			while [[ $state != "active" && $state != "clean" ]]; do
				sleep 5
				MD_Get_State_RAID $MD_RAID
				state=$RETURN_STR
			done

			MD_Save_RAID
			FIO_Device_Level_Test $MD_RAID
			tlog "mkfs -t $FILESYS $MD_RAID"
			tok mkfs -t $FILESYS $MD_RAID
			if [ ! -d /mnt/md_test ]; then
				mkdir /mnt/md_test
			fi
			tok mount -t $FILESYS $MD_RAID /mnt/md_test
			tok dd if=/dev/urandom of=/mnt/md_test/testfile bs=1M count=100
			md5sum /mnt/md_test/testfile > md5.old
			tok umount $MD_RAID

			Stop_Raid
			tok mdadm --assemble $MD_RAID $MD_DEV_LIST

			tok mount $MD_RAID /mnt/md_test
			md5sum /mnt/md_test/testfile > md5.3rd
			tok diff md5.3rd md5.old
			if [ $? -ne 0 ]; then
				tlog "FAIL: md5 checksum changed"
			else
				tlog "md5 checksum successfully"
			fi
			tok umount $MD_RAID

			FIO_Device_Level_Test $MD_RAID
			MD_Clean_RAID $MD_RAID
		done

		if [ $? -ne 0 ];then
			exit 1
		fi
	done
}

tlog "running $0"
trun "rpm -q mdadm || yum install -y mdadm"
trun "uname -a"
runtest
report_result
tend
