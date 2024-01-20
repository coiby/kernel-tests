#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	#Install fio
	trun which fio
	if [ $? -ne 0 ]; then
		install_fio
	fi

	MNT=/mnt/dax_device_add
	[ ! -d $MNT ] && mkdir $MNT

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 2 FSDAX
	local test_dev="$RETURN_STR"
	pmem_1="/dev/`echo $test_dev | awk '{print $1}'`"
	pmem_2="/dev/`echo $test_dev | awk '{print $2}'`"
#	pmem_3="/dev/`echo $test_dev | awk '{print $3}'`"

	tok pvcreate -f ${pmem_1} ${pmem_2}
	tok vgcreate -f pmem ${pmem_1}
	if [ $? -eq 1 ]; then
		tlog "FAIL: vgcreate pmem ${pmem_1} failed"
	else
		tlog "PASS: vgcreate pmem ${pmem_1} pass"
	fi
	tok lvcreate -l 90%FREE -n lv pmem -y
	if [ $? -eq 1 ]; then
		tlog "FAIL: lvcreate -l 90%FREE -n lv pmem -y failed"
	else
		tlog "PASS: lvcreate -l 90%FREE -n lv pmem -y pass"
	fi

	if rlIsRHEL 7; then
		tok mkfs.xfs -f /dev/mapper/pmem-lv
	elif rlIsRHEL ">=8"; then
		# shellcheck disable=SC2154
		tok mkfs.xfs $xfs_param -m reflink=0 -f /dev/mapper/pmem-lv
	fi

	tok mount -o dax,noatime /dev/mapper/pmem-lv $MNT
	tok "FIO_ENGINE_SUPPORT pmemblk"
	if (($? == 0)); then
		tlog "INFO: Executing fio pmemblk.fio on ${MNT} after lvcreated"
		tok fio pmemblk.fio
		if [ $? -eq 1 ]; then
			tlog "FAIL: fio pmemblk.fio on ${MNT} failed"
		else
			tlog "PASS: fio pmemblk.fio on ${MNT} pass"
		fi
	else
		tlog "fio engine pmemblk doesn't support on $(arch)"
	fi
	tok vgdisplay pmem
	tok lvextend -l +100%FREE /dev/mapper/pmem-lv
	if [ $? -eq 1 ]; then
		tlog "FAIL: lvextend -l +100%FREE /dev/mapper/pmem-lv failed"
	else
		tlog "PASS: lvextend -l +100%FREE /dev/mapper/pmem-lv pass"
	fi
	tok xfs_growfs ${MNT}
	tok umount /dev/mapper/pmem-lv
	if rlIsRHEL 7; then
		tok mkfs.xfs -f /dev/mapper/pmem-lv
	elif rlIsRHEL ">=8"; then
		tok mkfs.xfs $xfs_param -m reflink=0 -f /dev/mapper/pmem-lv
	fi
	tok mount -o dax,noatime /dev/mapper/pmem-lv ${MNT}
	tok "mount | grep dax"

	tok "FIO_ENGINE_SUPPORT pmemblk"
	if (($? == 0)); then
		tlog "INFO: Executing fio pmemblk.fio on ${MNT} after lvextend"
		tok fio pmemblk.fio
		if [ $? -eq 1 ]; then
			tlog "FAIL: fio pmemblk.fio on ${MNT} failed"
		else
			tlog "PASS: fio pmemblk.fio on ${MNT} pass"
		fi
	else
		tlog "fio engine pmemblk doesn't support on $(arch)"
	fi
	# add dax device
	tok vgextend -f pmem ${pmem_2}
	tok lvextend -l +100%FREE /dev/mapper/pmem-lv
	if [ $? -eq 1 ]; then
		tlog "FAIL: lvextend -l +100%FREE /dev/mapper/pmem-lv failed"
	else
		tlog "PASS: lvextend -l +100%FREE /dev/mapper/pmem-lv pass"
	fi

	tok "FIO_ENGINE_SUPPORT pmemblk"
	if (($? == 0)); then
		tlog "INFO: Executing fio pmemblk.fio on ${MNT} after dax device added"
		tok fio pmemblk.fio
		if [ $? -eq 1 ]; then
			tlog "FAIL: fio pmemblk.fio on ${MNT} failed"
		else
			tlog "PASS: fio pmemblk.fio on ${MNT} pass"
		fi
	else
		tlog "fio engine pmemblk doesn't support on $(arch)"
	fi

	# add non-dax device
	LOOP_DEVICE="`create_loop_devices 1 4096`"
	if [ -n "$LOOP_DEVICE" ]; then
		tlog "INFO: will use $LOOP_DEVICE for non-dax device add test"
		tok vgextend pmem $LOOP_DEVICE -y
		tnot lvextend -l +100%FREE /dev/mapper/pmem-lv
		if [ $? -eq 1 ]; then
			tlog "FAIL: non-dax lvextend -l +100%FREE /dev/mapper/pmem-lv failed"
		else
			tlog "PASS: non-dax lvextend -l +100%FREE /dev/mapper/pmem-lv pass"
		fi
	else
		tlog "INFO: no non-dax device"
	fi

	tok umount $MNT
	tok rm -fr $MNT
	tok vgremove -f pmem
	tok pvremove -f ${pmem_1} ${pmem_2} $LOOP_DEVICE
}

tlog "running $0"
trun "uname -a"
runtest

tend
