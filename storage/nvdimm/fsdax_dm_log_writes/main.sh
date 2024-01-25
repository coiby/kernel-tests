#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	#Install fio
	trun which fio
	if [ $? -ne 0 ]; then
		install_fio
	fi

	MNT=/mnt/dm_log_writes
	[ ! -d $MNT ] && mkdir $MNT

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 2 FSDAX
	local test_dev="$RETURN_STR"

	pmem_1=`echo $test_dev | awk '{print $1}'`
	pmem_2=`echo $test_dev | awk '{print $2}'`
	size1=`blockdev --getsize /dev/${pmem_1}`
	# shellcheck disable=SC2034
	size2=`blockdev --getsize /dev/${pmem_2}`

	tok "echo "0 $size1 log-writes /dev/${pmem_1} /dev/${pmem_2}" | dmsetup create log"
	if [ $? -eq 1 ]; then
		tlog "FAIL: dmsetup create dm-log-writes failed"
		return 1
	else
		tlog "PASS: dmsetup create dm-log-writes pass"
	fi

	# shellcheck disable=SC2154
	tok "mkfs.ext4 $ext4_param -F /dev/mapper/log"
	tok mount -o dax /dev/mapper/log $MNT
	tok "FIO_ENGINE_SUPPORT pmemblk"
	if (($? == 0)); then
		tlog "INFO: Executing fio pmemblk.fio on ${MNT}....."
		tok fio pmemblk.fio
		if [ $? -eq 1 ]; then
			tlog "FAIL: fio pmemblk.fio on ${MNT} failed"
		else
			tlog "PASS: fio pmemblk.fio on ${MNT} pass"
		fi
	else
		tlog "fio engine pmemblk not support on $(arch) platform"
	fi
	tok umount $MNT
	tok rm -fr $MNT
	tok dmsetup remove log
}

tlog "running $0"
trun "uname -a"
runtest

tend
