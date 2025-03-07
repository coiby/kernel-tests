#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	tok "find /sys -name deep_flush > deep_flush.txt"
	tok cat deep_flush.txt
	while read line
	do
		tlog "INFO: $line"
		deep_flush=`cat $line`
		if [ $deep_flush -eq 0 ]; then
			tlog "WPQ flush on all DIMMs doesn't support"
			tnot "echo 1 > $line"
		elif [ $deep_flush -eq 1 ]; then
			tlog "WPQ flush on all DIMMs support"
			tok "echo 1 > $line"
		fi
	done < deep_flush.txt
	rm deep_flush.txt
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
