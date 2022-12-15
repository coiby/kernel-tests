#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	ROOT_DISK=$(get_root_disk)

	if [[ "$ROOT_DISK" =~ "nvme" ]]; then
		tok "echo "System install on nvme ssd pass""
	else
		tnot "echo "System was not installed on nvme ssd""
		return 1
	fi
}

tlog "running $0"
trun "uname -a"
runtest
tend
