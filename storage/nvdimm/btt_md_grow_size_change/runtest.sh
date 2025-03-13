#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function LV_Create (){

	local disk_num=0
	LV_LIST=''

	# create pv, vg, lv on each disk
	# also get a list of lvs $lv_list which will be used as basic unit of md
	for disk in $devlist ; do
		disk="/dev/"$disk
		disk_num=$(($disk_num+1))
		tok pvcreate $disk -y
		if [ $? -ne 0 ]; then
			tlog "FAIL: Fail to create pv on $disk"
			exit 1
		fi
		tok vgcreate testvg$disk_num $disk
		if [ $? -ne 0 ]; then
			tlog "FAIL: Fail to create vg on $disk"
			exit 1
		fi
		tok lvcreate -L 300M -n testlv$disk_num testvg$disk_num
		if [ $? -ne 0 ]; then
			tlog "FAIL: Fail to create lv on testvg$disk_num"
			exit 1
		fi
		LV_LIST="$LV_LIST mapper/testvg$disk_num-testlv$disk_num"
	done

}

function LV_Delete (){

	local disk_num=0

	for disk in $devlist; do
		disk_num=$(($disk_num+1))
		tok vgremove -f testvg$disk_num
		if [ $? -ne 0 ]; then
			tlog "FAIL: Fail to remove vg testvg$disk_num"
			exit 1
		fi
		tok pvremove "/dev/"$disk
		if [ $? -ne 0 ]; then
			tlog "FAIL: Fail to remove pv $disk"
			exit 1
		fi
	done

}

function runtest() {

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

		for i in 1 4 5 6 10; do
			MD_RAID=''
			RETURN_STR=''
			seq_num=0
			raid_num=4
			spare_num=0

			if [ $i -eq 0 ];then
				bitmap=0
			else
				bitmap=1
			fi

			for disk in $devlist ; do
				disk="/dev/"$disk
				dd if=/dev/zero of=$disk bs=1M oflag=direct
			done
			LV_Create
			MD_Create_RAID $i "$LV_LIST" $raid_num $bitmap $spare_num
			if [ $? -ne 0 ];then
				tlog "FAIL: Failed to create md raid $RETURN_STR"
				LV_Delete
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

			tlog "mkfs -t $FILESYS $MD_RAID"
			tok mkfs -t $FILESYS $MD_RAID
			if [ ! -d /mnt/md_test ]; then
				mkdir /mnt/md_test
			fi
			tok mount -t $FILESYS $MD_RAID /mnt/md_test
			tok dd if=/dev/urandom of=/mnt/md_test/testfile bs=1M count=100
			md5sum /mnt/md_test/testfile > md5.old

			# resize lv
			for disk in $LOOP_DEVICE_LIST; do
				seq_num=$(($seq_num+1))
				tok lvextend -L +100M /dev/mapper/testvg$seq_num-testlv$seq_num
				if [ $? -ne 0 ]; then
					tlog "FAIL: Fail to extend lv testlv$disk_num"
				fi
			done

			# resize md
			tok mdadm --grow $MD_RAID --size=max
			if [ $? -ne 0 ]; then
				tlog "FAIL: Fail to grow $MD_RAID to max size"
			fi

			MD_Get_State_RAID $MD_RAID
			state=$RETURN_STR
			while [[ $state != "active" && $state != "clean" ]]; do
				sleep 5
				MD_Get_State_RAID $MD_RAID
				state=$RETURN_STR
			done
			tok umount $MD_RAID
			sleep 5
			tok mount $MD_RAID /mnt/md_test
			md5sum /mnt/md_test/testfile > md5.3rd
			if [ "`cat md5.3rd`" != "`cat md5.old`" ]; then
				tlog "FAIL: md5 checksum changed"
			fi
			tok umount $MD_RAID
			sleep 5

			FIO_Device_Level_Test $MD_RAID
			MD_Clean_RAID $MD_RAID
			LV_Delete "$devlist"

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
