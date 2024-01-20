#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	#Install fio
	trun which fio
	if [ $? -ne 0 ]; then
		install_fio
	fi
	tok "FIO_ENGINE_SUPPORT dev-dax"
	if (($? != 0)); then
		tlog "fio engine dev-dax doesn't support on $(arch), exit 1"
		exit 1
	fi
	num=4
	[[ $(arch) == "ppc64le" ]] && num=2
	# shellcheck disable=SC2154
	for align in $devdax_align; do
	        NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX $num DEVDAX $align
	        local test_dev="$RETURN_STR"

		for i in $test_dev; do
			cp dev-dax.fio dev-${i}-$align.fio -f
			sed -i "s#REPLACE#${i}#g" dev-${i}-$align.fio
			tlog "INFO: executing: fio dev-${i}-$align.fio background"
			tok "fio dev-${i}-$align.fio" &
		done
		wait
	done
}

tlog "running $0"
trun "uname -a"
runtest

tend
