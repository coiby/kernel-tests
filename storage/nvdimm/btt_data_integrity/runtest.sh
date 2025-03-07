#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	#Install dt
	install_dt

	sector_size_list="$SECTOR_SIZE_LIST"
	#FAIL: 4096
	sector_size_list="512"
	for sector_size in $sector_size_list; do

		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 BTT "$sector_size"
		local test_dev="$RETURN_STR"

		DT_IO_Test_Device_Level "$test_dev"
		if [ $? -eq 1 ]; then
			tlog "FAIL: dt device level test on $test_dev:$sector_size failed"
			exit 1
		else
			tlog "PASS: dt device level test on $test_dev:$sector_size pass"
		fi

		DT_IO_Test_File_Level "$test_dev"
		if [ $? -eq 1 ]; then
			tlog "FAIL: dt file level  test on $test_dev:$sector_size failed"
			exit 1
		else
			tlog "PASS: dt file level test on $test_dev:$sector_size pass"
		fi

	done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
