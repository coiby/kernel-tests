#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function namespace_create_test() {
CPU=$1
BASE_CMD="numactl --physcpubind=$CPU ndctl create-namespace -f -e $namespace"

#while true; do
for mode in raw fsdax devdax sector; do
	if [ "$mode" == "fsdax" ]; then
		for map in dev mem; do
			CMD="$BASE_CMD -m $mode -M $map"
			echo "$CMD"
			tok $CMD
		done
	elif [ "$mode" == "sector" ]; then
		for sector_size in $sector_size_list; do
			CMD="$BASE_CMD -m $mode -l $sector_size"
			echo $CMD
			tok $CMD
		done
	elif [ $mode == "devdax" ]; then
		for align in 2m 1g; do
			CMD="$BASE_CMD -m $mode -a $align"
			echo $CMD
			tok $CMD
		done
	elif [ "$mode" == "raw" ]; then
		CMD="$BASE_CMD -m $mode"
		echo "$CMD"
		tok $CMD
	fi
	done
#done
}

function runtest (){
	tok yum -y install numactl
	NR_CPUS=$(getconf _NPROCESSORS_ONLN)
	sector_size_list="$SECTOR_SIZE_LIST"

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 RAW

	local test_dev="$RETURN_STR"
	if [ ${test_dev} = "pmem0" -o ${test_dev} = "pmem1" ]; then
		m=${test_dev:4:1}
		NS=namespace$m.0
	else
		m=${test_dev:4:3}
		NS=namespace$m
	fi
	namespace=$NS
	((NR_CPUS--))
	for cpu in $(seq 0 $NR_CPUS); do
		namespace_create_test $cpu &
	done
	wait
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
