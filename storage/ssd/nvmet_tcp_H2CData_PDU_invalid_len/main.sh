#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest() {

	local num=0
	trun "yum -y install nvmetcli"
	tok "fallocate -l 100M /home/nvmedisk"
	tok "modprobe nvmet"
	if [ ! -f target.conf ]; then
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		exit 0
	fi
	if [ ! -f test1 ] && [ ! -f test2 ] && [ ! -f test3 ]; then
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		exit 0
	fi
	tok "nvmetcli restore ./target.conf"
	tok "chmod +x test1 test2 test3"
	while [ $num -lt 100 ]; do
		echo "Running test cylce $num" >/dev/kmsg
		tlog "Running test cylce $num"
		tok "./test1"
		tok "./test2"
		tok "./test3"
		sleep 0.05
		tok "./test1"
		sleep 0.05
		tok "./test2"
		sleep 0.05
		tok "./test3"
		((num++))
	done
	tok "nvmetcli clear"
}

tlog "running $0"
trun "uname -a"
runtest
tend
