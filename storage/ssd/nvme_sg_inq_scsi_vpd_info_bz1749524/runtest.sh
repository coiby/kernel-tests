#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	get_nvme_disk

for DISK in $DISKS; do
	tok "sg_inq /dev/$DISK | grep -Ei 'serial number:\ .*'"
done
}

tlog "running $0"
trun "uname -a"
runtest
tend
