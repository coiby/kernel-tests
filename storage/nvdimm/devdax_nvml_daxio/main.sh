#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	trun "yum -y install ndctl-devel daxctl-devel daxio"
	trun which daxio
	if (($? != 0)); then
		tlog "daxio doesn't exists on $(arch), return"
		return
	fi
	# shellcheck disable=SC2154
	for align in $devdax_align; do
		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 DEVDAX $align
		devlist=$RETURN_STR

		tok "daxio -z --output=/dev/$devlist"
		tok "daxio --input=/dev/$devlist --output=./myfile --len=2M --seek=4096"
		tok "cat /dev/zero | daxio --output=/dev/$devlist"
		tok "daxio --input=/dev/zero --output=/dev/$devlist --skip=4096"
	done
}

tlog "running $0"
trun "uname -a"
runtest

tend
