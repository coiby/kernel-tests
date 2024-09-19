#!/bin/sh

TNAME="storage/lvm/thinp/sanity"

# Source the common test script helpers
. ../../../../cki_lib/libcki.sh || exit 1

PS4='+ $(date "+%s.%N")\011 '
#set -x

IOZONE="iozone3_490"
LOOKASIDE="https://arr-cki-prod-lookaside.s3.us-east-1.amazonaws.com/lookaside/static"
function build_iozone
{
	echo "--- Download iozone ---"
	typeset target=$IOZONE
	typeset target_tarball=${target}.tar.gz
	typeset target_tarball_url="$LOOKASIDE/$target_tarball"

	rm -f $target_tarball
	wget --tries=10 -q $target_tarball_url || return 1

	echo "--- Extract iozone ---"
	rm -rf $target
	tar zxf $target_tarball || return 1

	echo "--- Build iozone ---"
	make -C $target/src/current/ linux || return 1
	cp -f $target/src/current/iozone ./iozone || return 1

	return 0
}

storage_path=/var/tmp
i=0
ret=0

function make_storage_file()
{
	local retval="$1"
	local name="$2"
	local size="$3"
	fallocate -l$size $storage_path/$name &>> $OUTPUTFILE
	if [ $? -ne 0 ]; then
		echo "Failed creating $storage_path/$name" | tee -a $OUTPUTFILE
		return 1
	fi
	eval $retval="$storage_path/$name"
	return 0
}

function make_loop_dev()
{
	local retval="$1"
	local size="$2"
	local loname=$(losetup -f)
	local storage=""

	i=$((i+1))
	make_storage_file storage storage$i $size

	losetup $loname $storage
	if [ $? -ne 0 ]; then
		echo "Failed setting up loopdev $loname for $storage" | tee -a $OUTPUTFILE
		return 1
	fi
	eval $retval="$loname"
	return 0
}

function clean_loop_dev()
{
	local loopdev=$1
	local file=$(losetup $loopdev | awk '{print $3}' | sed 's/^(//' | sed 's/)$//')
	losetup -d $loopdev
	test -f "$file" && rm -f $file
}


function rcmd()
{
	local cmd="$*"
	local _ret=0
	echo "$cmd" | tee -a $OUTPUTFILE
	eval $cmd > cmdlog.txt 2>&1
	_ret=$?
	cat cmdlog.txt | tee -a $OUTPUTFILE
	echo " --> ret $_ret" | tee -a $OUTPUTFILE
	ret=$((ret | $_ret))
}

size_free=`df -BM $storage_path | tail -1 | awk '{ print $4 }' | sed "s/M//"`
# in M, adjust this manually according to make_loop_dev loopdev1 commands below
size_requested=1024

# SKIP test if there's not enough space on target device
if [[ $size_requested -gt $size_free ]]; then
	rstrnt-report-result $TNAME SKIP 0
	exit 0
fi

# Build IOZONE for later use
build_iozone
if [ $? -ne 0 ]; then
	echo "Oops, failed to build iozone" | tee -a $OUTPUTFILE
	rstrnt-report-result $TNAME FAIL 1
	exit 0
fi

rcmd make_loop_dev loopdev1 512M
rcmd make_loop_dev loopdev2 512M

# shellcheck disable=SC2154
devs="$loopdev1 $loopdev2"

rcmd pvcreate -ff $devs
rcmd pvs

rcmd vgcreate myvg $devs
rcmd vgs

for j in `seq 1 4`; do
	rcmd lvremove -ff myvg
	rcmd lvcreate -l 100%PV -T myvg/mythinpool
done

rcmd lvs

for j in `seq 1 4`; do
	rcmd lvcreate -V512M -T myvg/mythinpool -n thinvolume$j
	rcmd mkdir -p /mnt/testmnt$j
	# use noalign option to fix error: internal log size is too large
	# mkfs.xfs has increased the minimum log size to 64MB in newer version
	# This is causing an error when creating xfs on 512MB thinvol
	# in case noalign option would cause some troubles(performance etc.),
	# thinvol size has to be increased
	if cki_is_kernel_automotive; then
		#automotive only support ext4 fs
		rcmd mkfs.ext4 -F /dev/mapper/myvg-thinvolume$j
	else
		rcmd mkfs.xfs -fd noalign /dev/mapper/myvg-thinvolume$j
	fi
	rcmd mount /dev/mapper/myvg-thinvolume$j /mnt/testmnt$j
	rcmd umount /mnt/testmnt$j

	rcmd lvcreate -s -kn --name mysnapshot$j myvg/thinvolume$j
	rcmd mount /dev/mapper/myvg-mysnapshot$j /mnt/testmnt$j
	rcmd umount /mnt/testmnt$j

	rcmd lvcreate -s -kn --name mysnapshot2$j myvg/mysnapshot$j
	rcmd mount /dev/mapper/myvg-mysnapshot2$j /mnt/testmnt$j
	rcmd umount /mnt/testmnt$j
done

rcmd lvs

for j in `seq 1 2`; do
	rcmd mount /dev/mapper/myvg-thinvolume$j /mnt/testmnt$j
	./iozone -f /mnt/testmnt$j/testfile -B -s 32535 -m 2 -Z
	rcmd umount /mnt/testmnt$j

	rcmd mount /dev/mapper/myvg-mysnapshot$j /mnt/testmnt$j
	./iozone -f /mnt/testmnt$j/testfile -B -s 32535 -m 2 -Z
	rcmd umount /mnt/testmnt$j

	rcmd mount /dev/mapper/myvg-mysnapshot2$j /mnt/testmnt$j
	./iozone -f /mnt/testmnt$j/testfile -B -s 32535 -m 2 -Z
	rcmd umount /mnt/testmnt$j
done

rcmd lvs
rcmd ls -la /dev/mapper

rcmd lvremove -ff myvg

rcmd vgremove -ff myvg
rcmd pvremove -ff $devs

rcmd clean_loop_dev $loopdev1
rcmd clean_loop_dev $loopdev2

rcmd lvs
rcmd vgs
rcmd pvs

echo "Test finished" | tee -a $OUTPUTFILE

if [ $ret -eq 0 ]; then
	rstrnt-report-result $TNAME PASS 0
else
	rstrnt-report-result $TNAME FAIL $ret
fi

exit 0
