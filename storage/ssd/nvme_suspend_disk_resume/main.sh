#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest() {
	install_fio

	get_nvme_disk

	partition_1_primary "$DISKS"

	prepare_reboot

	suspend_resume disk 180
}

tlog "running $0"
trun "uname -a"
tlog "REBOOTCOUNT=$REBOOTCOUNT"
if [ "$REBOOTCOUNT" -eq 0 ]; then
	add_kernel_option
elif [ "$REBOOTCOUNT" -eq 1 ]; then
	runtest
else
	tlog "$0 test completed"
fi
tend
