#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	#Install fio
	trun which fio
	if [ $? -ne 0 ]; then
		install_fio
	fi

	#Install iozone
	trun which iozone
	if [ $? -ne 0 ]; then
		install_iozone
	fi

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 FSDAX
	local test_dev="$RETURN_STR"

	Iozone_6_Process_Test "$test_dev"
	if [ $? -eq 1 ]; then
		tlog "FAIL: iozone test on $test_dev failed"
		exit 1
	else
		tlog "PASS: iozone test on $test_dev pass"
	fi

	FIO_Device_Level_Test "$test_dev"
	if [ $? -eq 1 ]; then
		tlog "FAIL: fio device level test on $test_dev failed"
		exit 1
	else
		tlog "PASS: fio device level test on $test_dev pass"
	fi
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
