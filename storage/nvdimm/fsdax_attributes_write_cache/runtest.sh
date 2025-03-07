#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	num=4
	[[ $(arch) == "ppc64le" ]] && num=2
	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX $num FSDAX
	devlist=$RETURN_STR
	echo $devlist
	tok "find /sys -name write_cache | grep "pmem.*dax" > write_cache.txt"
	tok cat write_cache.txt
	while read line
	do
		tlog "INFO: $line"
		write_cache=`cat $line`
		if [ $write_cache -eq 0 ]; then
			tlog "INFO: write_cache disabled"
			if [ $write_cache -eq 0 ]; then
				tlog "tlog: write_cache disabled, enable it"
				tok "echo 1 > $line"
			fi
		elif [ $write_cache -eq 1 ]; then
			tlog "INFO: write_cache enabled, disable it"
			tok "echo 0 > $line"
			write_cache=`cat $line`
			if [ $write_cache -eq 0 ]; then
				tlog "tlog: write_cache disabled, enable it"
				tok "echo 1 > $line"
			fi
		fi
	done < write_cache.txt
	rm -f write_cache.txt
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
