#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function error_inject ()
{
	NAMESPACE=$1
	tok ndctl inject-error --block=12 --count=2 $NAMESPACE
	tok ndctl start-scrub
	tok ndctl wait-scrub
	tok ndctl inject-error --uninject --block=12 --count=2 $NAMESPACE
	tok ndctl inject-error --status $NAMESPACE
	tok ndctl clear-errors $NAMESPACE
}

function runtest (){
	sector_size_list="$SECTOR_SIZE_LIST"
			echo $sector_size_list

			#For RAW
			NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 RAW
			local test_dev="$RETURN_STR"
			NS=$(ndctl list | grep -oE "namespace.*[0-9]")
			error_inject $NS

#			#For BTT
#			for sector_size in $sector_size_list; do
#				NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 BTT $sector_size
#				local test_dev="$RETURN_STR"
#				NS=`ndctl list | grep -oE namespace.*[0-9]`
#				error_inject $NS
#			done

			#For FSDAX
			NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 FSDAX
			local test_dev="$RETURN_STR"
			NS=$(ndctl list | grep -oE "namespace.*[0-9]")
			error_inject $NS

			#For DEVDAX
			for align_size in 2M 1G; do
				NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 1 DEVDAX $align_size
				local test_dev="$RETURN_STR"
				NS=$(ndctl list | grep -oE "namespace.*[0-9]")
				error_inject $NS
			done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
