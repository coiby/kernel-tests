#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest() {

	if rlIsRHEL 9 || rlIsRHEL 10; then
		trun "yum -y install fio-engine-pmemblk fio-engine-dev-dax fio-engine-libpmem libpmem-devel libpmemblk-devel --skip-broken"
	else
		trun "yum -y module enable pmdk"
		tok "yum -y install libaio-devel zlib-devel libpmem* daxio --skip-broken"
	fi

	install_fio

	prepare_reboot

	tok "FIO_ENGINE_SUPPORT dev-dax"
	ret=$?
	if ((ret != 0)); then
		tlog "fio engine dev-dax doesn't support, exit 1"
		exit 1
	fi

	NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX 2 DEVDAX 2m
	local test_devs="$RETURN_STR"

	# shellcheck disable=SC2086
	for test_dev in $test_devs; do
		cp dev-dax.fio dev-"$test_dev"-2m.fio -f
		sed -i "s#REPLACE#${test_dev}#g" dev-${test_dev}-2m.fio
		tlog "INFO: executing: fio dev-${test_dev}-2m.fio background"
		tok "fio dev-${test_dev}-2m.fio" &
	done

	tok rtcwake -m disk -s 180

	wait

}

tlog "running $0"
trun "uname -a"
tlog "REBOOTCOUNT=$REBOOTCOUNT"
if [ "$REBOOTCOUNT" -eq 0 ]; then
	add_kernel_option
elif [ "$REBOOTCOUNT" -eq 1 ]; then
	runtest
else
	tlog "$0 test completed"
fi
tend
