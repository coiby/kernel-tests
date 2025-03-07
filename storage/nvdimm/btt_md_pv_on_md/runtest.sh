#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest() {

	devlist=''

	sector_size_list="$SECTOR_SIZE_LIST"
	for sector_size in $sector_size_list; do

		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 4 BTT "$sector_size"
		devlist=$RETURN_STR

		for level in 0 1 4 5 6 10; do

			RETURN_STR=''
			MD_RAID=''
			spare_num=0
			raid_num=4

			if [ $level -eq 0 ]; then
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
			tok pvcreate $MD_RAID -y
			if [ $? -ne 0 ]; then
				tlog "FAIL: fail to create pv on $MD_RAID"
			fi
			tok vgcreate vg_md_test $MD_RAID
			if [ $? -ne 0 ]; then
				tlog "FAIL: fail to create vg on $MD_RAID"
			fi
			tok lvcreate -l 100%FREE -n lv_md_test vg_md_test
			if [ $? -ne 0 ]; then
				tlog "FAIL: fail to create lv on vg vg_md_test"
			fi
			FIO_Device_Level_Test /dev/vg_md_test/lv_md_test
			sleep 60
			tok vgremove -f vg_md_test
			if [ $? -ne 0 ]; then
				tlog "FAIL: fail to remove vg vg_md_test"
			fi
			tok pvremove $MD_RAID
			if [ $? -ne 0 ]; then
				tlog "FAIL: fail to remove pv"
			fi
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
