#!/bin/bash

# Copyright 2017, Red Hat, Inc.
# Author: Jeff Moyer <jmoyer@redhat.com>
# License: GPLv2+
#
# Test the badblocks handling code for pmem.
#
# Mount the file system with -o dax
# Create a file of PAGE_SIZE bytes
# get the block mapping for the file
# mark the region bad
# mmap the file and try to do a load from the mmap'd region
# try to clear the error by overwriting the file
#

if [ $# -ne 2 ]; then
	echo "Usage: $0 <dev> <mountpoint>"
	exit 1
fi

DEV=$1
MNT=$2
file=$(mktemp $MNT/tmp.XXXXXXXXXX)
devname=$(basename $DEV)

pagesize=$(getconf PAGESIZE)

function fail()
{
	echo "$1"
	exit 1
}

umount $MNT >&/dev/null
mount -o dax $DEV $MNT || fail "unable to mount fs"

dd if=/dev/zero of=$file bs=$pagesize count=1 || fail "unable to write to file"

start=$(xfs_io -c "fiemap" $file | tail -1 | sed -e 's/.*:.*: \([0-9]\+\)\.\.[0-9]\+/\1/g')

echo "$start 1" > /sys/block/$devname/badblocks

# sigbus <file> <offset into file of bad block>
./sigbus $file 0
RET=$?

rm $file
umount $MNT

if [ $RET -ne 0 ]; then
	echo "FAIL"
	exit 1
fi

echo "PASS"
