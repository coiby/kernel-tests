#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function run_blktests() {

	local test_dev="/dev/$1"
	testcases="block/004 block/007 block/008 block/012 block/036"
	if [ ! -d "blktests" ]; then
		tok "git clone https://github.com/osandov/blktests"
		tok "cd blktests && make"
	fi
	tok "cd blktests && echo TEST_DEVS=\($test_dev\) > config && ./check $testcases"
}


function runtest (){

	tlog "Start blktests with nvdimm sector mode"
	sector_size_list="$SECTOR_SIZE_LIST"
	for sector_size in $sector_size_list; do
		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 BTT "$sector_size"
		run_blktests "$RETURN_STR"
	done

	tlog "Start blktests with nvdimm fsdax mode"
	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 FSDAX
	run_blktests "$RETURN_STR"

	tlog "Start blktests with nvdimm raw mode"
	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 RAW
	run_blktests "$RETURN_STR"
}

tlog "running $0"
trun "uname -a"
runtest

tend
