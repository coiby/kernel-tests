#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	if [ -f ./vma-split.c ]; then
		tok gcc -O0 -g3 -W -o vma-split vma-split.c
	else
		tlog "INFO: no test file vma-split.c"
		exit 1
	fi
	# shellcheck disable=SC2154
	for align in $devdax_align; do
		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 DEVDAX $align
		local test_dev="$RETURN_STR"

		tok ./vma-split /dev/$test_dev $align

	done
}

tlog "running $0"
trun "uname -a"
runtest

tend
