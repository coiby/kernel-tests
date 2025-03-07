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
	sector_size_list="$SECTOR_SIZE_LIST"
	for sector_size in $sector_size_list; do

		NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 BTT "$sector_size"
		local test_dev="$RETURN_STR"
		if [ ${test_dev} = "pmem0s" ] || [ ${test_dev} = "pmem1s" ]; then
			m=${test_dev:4:1}
			NS=namespace$m.0
		else
			m=${test_dev:4:3}
			NS=namespace$m
		fi
		tok ndctl list -n $NS
		size=`ndctl list -n $NS -H | grep \"size\" | grep -o "[0-9].*[0-9]"`
		tlog "INFO: BTT device: $test_dev sector_size:$sector_size size:$size"
	done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
