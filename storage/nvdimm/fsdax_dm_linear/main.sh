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

	MNT=/mnt/dm_linear
	[ ! -d $MNT ] && mkdir $MNT

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 2 FSDAX
	local test_dev="$RETURN_STR"

	pmem_1=`echo $test_dev | awk '{print $1}'`
	pmem_2=`echo $test_dev | awk '{print $2}'`
	size1=`blockdev --getsize /dev/${pmem_1}`
	size2=`blockdev --getsize /dev/${pmem_2}`

	echo "0 $size1 linear /dev/${pmem_1} 0
$size1 $size2 linear /dev/${pmem_2} 0" | dmsetup create joined
	if [ $? -eq 1 ]; then
		tlog "FAIL: dmsetup create joined failed"
		return 1
	else
		tlog "PASS: dmsetup create joined pass"
	fi
	# shellcheck disable=SC2154
	tok "mkfs.ext4 $ext4_param -F /dev/mapper/joined"

	tok mount -o dax /dev/mapper/joined $MNT
	trun "FIO_ENGINE_SUPPORT pmemblk"
	if (($? == 0)); then
		tlog "INFO: Executing fio pmemblk.fio on ${MNT}....."
		tok fio pmemblk.fio
		if [ $? -eq 1 ]; then
			tlog "FAIL: fio pmemblk.fio on ${MNT} failed"
		else
			tlog "PASS: fio pmemblk.fio on ${MNT} pass"
		fi
	else
		tlog "fio engine pmemblk doesn't support on $(arch)"
	fi

	tok umount $MNT
	tok rm -fr $MNT
	tok dmsetup remove joined
}

tlog "running $0"
trun "uname -a"
runtest

tend
