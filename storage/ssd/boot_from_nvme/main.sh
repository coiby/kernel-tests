#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
. $CDIR/../../../cki_lib/libcki.sh
. $CDIR/../../include/bash_modules/lxt/include.sh || exit 200

function runtest() {

	ROOT_DISK=$(get_root_disk)

	if [[ "$ROOT_DISK" =~ "nvme" ]]; then
		tok "echo "System installed on $ROOT_DISK""
	else
		tnot "echo "System was not installed on nvme ssd""
		return 1
	fi
}

tlog "running $0"
trun "uname -a"
runtest
tend
