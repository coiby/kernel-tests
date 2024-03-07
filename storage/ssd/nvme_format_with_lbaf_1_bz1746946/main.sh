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
	MODEL=$(cat /sys/block/"$DISK"/device/model)
	if [[ $MODEL =~ "INTEL SSDPEDMD016T4" ]]; then
		#BZ2097565
		tnot "nvme format --lbaf=1 /dev/$DISK -f"
	elif [[ $MODEL =~ "Dell Express Flash NVMe P4800X" ]]; then
		tlog "$DISK: format will take long time, skipping it"
		continue
	else
		tok "nvme format --lbaf=1 /dev/$DISK -f"
	fi
	tok "lsblk | grep nvme"
	tok "nvme reset /dev/${DISK:0:5}"
	tok "nvme format /dev/$DISK --lbaf=0 -f"

done
}

tlog "running $0"
trun "uname -a"
runtest
tend
