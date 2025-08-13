#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest() {
	install_fio

	prepare_reboot

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 2 BTT 512

	local test_dev="$RETURN_STR"

	# shellcheck disable=SC2086
	suspend_resume disk 180 $test_dev
}

tlog "running $0"
trun "uname -a"
tlog "REBOOTCOUNT=$REBOOTCOUNT"
if [ "$REBOOTCOUNT" -eq 0 ]; then
	add_kernel_option
elif [ "$REBOOTCOUNT" -eq 1 ]; then
	runtest
	report_result
else
	tlog "$0 test completed"
fi
tend
