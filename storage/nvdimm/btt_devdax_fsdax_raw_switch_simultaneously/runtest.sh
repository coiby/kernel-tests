#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function btt_fsdax_raw_devdax_switch() {
	for sector_size in $sector_size_list; do
		tok ndctl create-namespace -f -e namespace"${1}".0 --mode=sector -l "$sector_size"
		tok ndctl create-namespace -f -e namespace"${1}".0 --mode=fsdax
		tok ndctl create-namespace -f -e namespace"${1}".0 --mode=raw
		tok ndctl create-namespace -f -e namespace"${1}".0 --mode=devdax
	done
}

function btt_fsdax_raw_devdax_switch_ns() {
	NS=$1
	for sector_size in $sector_size_list; do
		tok "ndctl create-namespace -f -e $NS --mode=sector -l $sector_size | tee temp_ns"
		NS=$(cat temp_ns | grep -oE namespace.*[0-9])
		tok "ndctl create-namespace -f -e $NS --mode=fsdax | tee temp_ns"
		NS=$(cat temp_ns | grep -oE namespace.*[0-9])
		tok "ndctl create-namespace -f -e $NS --mode=raw | tee temp_ns"
		NS=$(cat temp_ns | grep -oE namespace.*[0-9])
		tok "ndctl create-namespace -f -e $NS --mode=devdax | tee temp_ns"
		NS=$(cat temp_ns | grep -oE namespace.*[0-9])
	done
}

function runtest (){
	num=0
	sector_size_list="$SECTOR_SIZE_LIST"
	while [ $num -lt 1 ]; do
		hn=$(hostname)
		if [[ "$hn" =~ "hpe-dl380gen9" ]]; then
			for i in 0 1 2 3; do
				btt_fsdax_raw_devdax_switch $i &
			done
		else
			#For AEP NVDIMM
			NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 4 RAW
			local test_dev="$RETURN_STR"
			for((i=0;i<4;i++)); do
				((num=$i+1))
				NS_List[$i]=$(ndctl list | grep -oE namespace.*[0-9] | head -$num | tail -1)
			done
			for((i=0;i<4;i++)); do
				btt_fsdax_raw_devdax_switch_ns "${NS_List[$i]}" &
			done
			wait
		fi
		((num++))
	done

}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
