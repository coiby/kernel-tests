#!/bin/bash
# common routines to include.

#source rhts environment
. /usr/bin/rhts_environment.sh

# /mnt/testarea can be overwritten by tests, like ltp/generic
TDIR=/mnt/kcov
mkdir -p $TDIR
KCOV_CONF=$TDIR/kcov.conf
KCOV_KDIR=
KCOV_INFO_LIST=$TDIR/kernel_tests_name.lst
KCOV_COMBINED_NAME=kcov.combined.info
REPO=http://download.devel.redhat.com/qa/rhts/lookaside/gcov_kernels

RHEL_KRNL=( \
	[80]=4.18.0-80.el8 \
	[81]=4.18.0-147.el8 \
	[82]=4.18.0-193.el8 \
	[83]=4.18.0-233.el8 \
	[84]=4.18.0-304.el8 \
)

log()
{
	echo $1 | tee -a $OUTPUTFILE
}

fail()
{
	if [ -n "$2" ]; then
		log "FAIL: $2"
	fi

	if [ -n "$1" ]; then
		report_result $TEST/$1 FAIL $SCORE
	else
		report_result $TEST FAIL $SCORE
	fi
}

pass()
{
	if [ -n "$1" ]; then
		report_result $TEST/$1 PASS $SCORE
	else
		report_result $TEST PASS $SCORE
	fi
}

load_config()
{
	KCOV_KDIR=$(awk -F= '$1~/KDIR/{print $2}' $KCOV_CONF)
	KCOV_ONLY_FINAL_INFO=$(awk -F= '$1~/ONLY_FINAL_INFO/{print $2}' $KCOV_CONF)
	if [ -n "$KCOV_KDIR" ]; then
		KDIR_OPT=" --kernel-directory ${KCOV_KDIR//,/ --kernel-directory } "
	else
		KDIR_OPT=""
	fi

	KCOV_TEST_NAME=${TEST_NAME:-kernel tests}
	CLEANED_NAME=${KCOV_TEST_NAME// /-}
	CLEANED_NAME=${CLEANED_NAME//\//_}
	KCOV_BASE_INFO=$TDIR/"$CLEANED_NAME".base.info
	KCOV_TEST_INFO=$TDIR/"$CLEANED_NAME".test.info
	KCOV_ALL_INFO=$TDIR/"$CLEANED_NAME".info
	KCOV_COMBINED_INFO=$TDIR/$KCOV_COMBINED_NAME
}

submit_info()
{
	if [[ $KCOV_ONLY_FINAL_INFO != 'true' ]]; then
		rhts-submit-log -l "$1"
	fi
}

install_lcov()
{
	log "install lcov"
	if ! which lcov; then
		git clone https://github.com/linux-test-project/lcov.git
		cd lcov
		git checkout aa56a43774e54955f5ca7ab798a7b0babdd13cb1
		make install
		cd ..
	fi

	if ! which lcov; then
		fail prepare "failed ot install lcov"
		exit
	fi
}

if [ -n "$DEBUG" ]; then
	set -x
fi
