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

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 FSDAX
	local test_dev="$RETURN_STR"

	DEV=/dev/${test_dev}
	MNT=/mnt/dax
	[ ! -d "$MNT" ] && mkdir $MNT
	devname=$(basename $DEV)
	pagesize=$(getconf PAGESIZE)

	# shellcheck disable=SC2154
	tok mkfs.ext4 $ext4_param -F $DEV
	tok mount -o dax $DEV $MNT

	file=$(mktemp $MNT/tmp.XXXXXXXXXX)
	tok dd if=/dev/zero of=$file bs=$pagesize count=1

#	start=$(xfs_io -c "fiemap" $file | tail -1 | sed -e 's/.*:.*: \([0-9]\+\)\.\.[0-9]\+/\1/g')
	start=$(filefrag -v -b512 $file | grep -E "^[ ]+[0-9]+.*" | head -1 | awk '{ print $4 }' | cut -d. -f1)
	tok "echo "$start 8" > /sys/block/$devname/badblocks"

#	tnot "xfs_io -c 'mmap 0 $pagesize' -c 'mread 0 $pagesize' $file"
	tnot "dd if=$file of=/dev/null iflag=direct bs=4096 count=1"
	if [ $? -eq 1 ]; then
		tlog "FAIL: LOAD allowed from bad block!"
	fi

	# Clear the error
	tok dd if=/dev/zero of=$file bs=$pagesize count=1

	rm $file
	tok umount $MNT >&/dev/null
	tok rm -fr $MNT
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
