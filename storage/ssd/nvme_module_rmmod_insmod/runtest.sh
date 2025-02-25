#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	tlog "check whether nvme module insmod"
	trun "lsmod | grep -i nvme"
	if [ $? -eq 0 ]; then
		tlog "nvme module insmod"
	else
		tlog "nvme module not insmod"
		tok "modprobe nvme"
	fi
	num=0
	while [ $num -lt 500 ]; do
		tlog "nvme module rmmod/insmod:$num"
		tok "modprobe -fr nvme"
		if [ $? -ne 0 ]; then
			tlog "nvme module rmmod failed:$num"
			break
		fi
		sleep 0.5
		tok "modprobe nvme"
		if [ $? -ne 0 ]; then
			tlog "nvme module insmod failed:$num"
			break
		fi
		((num++))
		sleep 0.5
	done
	tlog "nvme module rmmod/insmod finished:$num"
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
