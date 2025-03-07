#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	#Install fio
	install_fio

	#Install iozone
	install_iozone

	sector_size_list="$SECTOR_SIZE_LIST"
	for sector_size in $sector_size_list; do

		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 BTT "$sector_size"
		local test_dev="$RETURN_STR"

		Iozone_6_Process_Test "$test_dev"
		if [ $? -eq 1 ]; then
			tlog "FAIL: iozone test on $test_dev:$sector_size failed"
			exit 1
		else
			tlog "PASS: iozone test on $test_dev:$sector_size pass"
		fi

		FIO_Device_Level_Test "$test_dev"
		if [ $? -eq 1 ]; then
			tlog "FAIL: fio device level test on $test_dev:$sector_size failed"
			exit 1
		else
			tlog "PASS: fio device level test on $test_dev:$sector_size pass"
		fi

	done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
