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
	mkdir /mnt/fortest

	which mkfs.ext4
	if [ $? -eq 0 ]; then
		FILESYS="ext4"
	else
		FILESYS="ext3"
	fi

	tok dd if=/dev/urandom of=bigfile bs=1M count=2048
	if [ $? -ne 0 ]; then
	      tlog "Create bigfile failed"
	      exit 1;
	fi
	md5sum bigfile > md5sum1


	sector_size_list="$SECTOR_SIZE_LIST"
	for sector_size in $sector_size_list; do

		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 4 BTT "$sector_size"
		devlist=$RETURN_STR
		firstdisk=$(echo $devlist | cut -d ' ' -f 1)
		firstdisk="/dev/"$firstdisk

		RAID_LIST="1 4 5 6 10"
		for level in $RAID_LIST; do

			RETURN_STR=''
			MD_RAID=''
			raid_num=4
			bitmap=1
			spare_num=0
			cnt=12

			MD_Create_RAID $level "$devlist" $raid_num $bitmap $spare_num
			if [ $? -ne 0 ];then
				tlog "FAIL: Failed to create md raid $RETURN_STR"
				break
			else
				tlog "INFO: Successfully created md raid $RETURN_STR"
			fi
			MD_RAID="$RETURN_STR"

			MD_Get_State_RAID $MD_RAID
			state="$RETURN_STR"

			while [[ $state != "active" && $state != "clean" ]]; do
				sleep 5
				MD_Get_State_RAID $MD_RAID
				state="$RETURN_STR"
			done

			tok mkfs -t $FILESYS $MD_RAID
			if [ ! -d "/mnt/fortest" ]; then
				mkdir /mnt/fortest
			fi
			tok mount -t $FILESYS $MD_RAID /mnt/fortest

			while [ $cnt -ne 0 ]; do

				tlog "INFO: cnt:$cnt"
				tok rm -rf /mnt/fortest/bigfile
				tok cp bigfile /mnt/fortest &
				sleep 10
				tok mdadm $MD_RAID -f $firstdisk
				sleep 5
				trun mdadm $MD_RAID -r $firstdisk
				rt=$?
				rm_num=10
				while [ $rm_num -ne 0 ]; do
					if [ $rt -ne 0 ];then
						sleep 30
						trun mdadm $MD_RAID -r $firstdisk
						rt=$?
						((rm_num--))
					else
						break
					fi
				done
				sleep 30
				tok mdadm $MD_RAID -a $firstdisk

				#wait for cp file operation done
				num=$(ps auxf | grep cp | grep bigfile | wc -l)
				while [ $num -ne 0 ]; do
					sleep 10
					num=$(ps auxf | grep cp | grep bigfile | wc -l)
				done
				wait
				tok sync
				tlog "cp done"

				reco=`cat /proc/mdstat  | grep recovery`
				while [ -n "$reco" ]; do
					  sleep 10
					reco=`cat /proc/mdstat  | grep recovery`
				done
				tlog "recovery done"

				md5sum /mnt/fortest/bigfile > md5sum2
				tmp1=`awk '{print $1}' ./md5sum1`
				tmp2=`awk '{print $1}' ./md5sum2`
				echo $tmp1 > a
				echo $tmp2 > b
				tok diff a b
				if [ $? -ne 0 ]; then
					tlog "There are some date interruption, cnt is $cnt"
				fi

				cnt=$(($cnt-1))
			done

			tok umount $MD_RAID
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
