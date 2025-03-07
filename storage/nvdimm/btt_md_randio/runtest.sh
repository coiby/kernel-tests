#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
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
	which fio
	if [ $? -eq 0 ]; then
		tlog "INFO: Fio has been installed"
	else
		install_fio
	fi

	sector_size_list="$SECTOR_SIZE_LIST"
	for sector_size in $sector_size_list; do
		echo $sector_size_list
		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 4 BTT "$sector_size"
		devlist=$RETURN_STR

		RAID_LIST="0 1 4 5 6 10"
		for level in $RAID_LIST; do

			RETURN_STR=''
			MD_RAID=''
			MD_DEV_LIST=''
			spare_num=0
			raid_num=4
			runtime=10
			numjobs=30

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

			tok fio -filename=$MD_RAID -iodepth=1 -thread -rw=randread -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -bs_unaligned -runtime=$runtime -time_based -size=1G -group_reporting -name=mytest -numjobs=$numjobs
			tok fio -filename=$MD_RAID -iodepth=1 -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -bs_unaligned -runtime=$runtime -time_based -size=1G -group_reporting -name=mytest -numjobs=$numjobs
			sync
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
