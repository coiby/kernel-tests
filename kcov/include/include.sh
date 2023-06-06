#!/bin/bash
# common routines to include.

. ../../cki_lib/libcki.sh || exit 1

# /mnt/testarea can be overwritten by tests, like ltp/generic
TDIR=/mnt/kcov
mkdir -p $TDIR
KCOV_CONF=$TDIR/kcov.conf
KCOV_KDIR=
export KCOV_INFO_LIST=$TDIR/kernel_tests_name.lst
KCOV_COMBINED_NAME=kcov.combined.info

KERNEL_GCOV="kernel-gcov"
if cki_is_kernel_automotive; then
	KERNEL_GCOV="kernel-automotive-gcov"
fi

GCOV_BASEDIR=$(rpm -ql ${KERNEL_GCOV} | grep -F -m 1 "$(uname -r)")

log()
{
	echo "$1" | tee -a "$OUTPUTFILE"
}

fail()
{
	if [ -n "$2" ]; then
		log "FAIL: $2"
	fi

	if [ -n "$1" ]; then
		rstrnt-report-result "$TEST"/"$1" FAIL "$SCORE"
	else
		rstrnt-report-result "$TEST" FAIL "$SCORE"
	fi
}

pass()
{
	if [ -n "$1" ]; then
		rstrnt-report-result "$TEST/$1" PASS "$SCORE"
	else
		rstrnt-report-result "$TEST" PASS "$SCORE"
	fi
}

load_config()
{
	KCOV_KDIR=$(awk -F= '$1~/KDIR/{print $2}' $KCOV_CONF)
	KCOV_ONLY_FINAL_INFO=$(awk -F= '$1~/ONLY_FINAL_INFO/{print $2}' $KCOV_CONF)
	if [ -z "$KCOV_KDIR" ]; then
		# lcov to collect the results for the test can only use directories currently loaded.
		KCOV_KDIR=$(ls --format=commas /sys/kernel/debug/gcov/"$GCOV_BASEDIR"/)
	fi
	log "collecting coverage from directories: ${KCOV_KDIR}"
	export KDIR_OPT=" --kernel-directory ${KCOV_KDIR//,/ --kernel-directory } "

	KCOV_TEST_NAME=${TEST_NAME:-kernel tests}
	CLEANED_NAME=${KCOV_TEST_NAME// /-}
	CLEANED_NAME=${CLEANED_NAME//\//_}
	export KCOV_BASE_INFO=$TDIR/"$CLEANED_NAME".base.info
	export KCOV_TEST_INFO=$TDIR/"$CLEANED_NAME".test.info
	export KCOV_ALL_INFO=$TDIR/"$CLEANED_NAME".info
	export KCOV_COMBINED_INFO=$TDIR/$KCOV_COMBINED_NAME
}

submit_info()
{
	if [[ $KCOV_ONLY_FINAL_INFO != 'true' ]]; then
		cki_upload_log_file "$1"
	fi
}

install_lcov()
{
	log "install lcov"
	if ! which lcov; then
		repo_url="https://github.com/linux-test-project/lcov.git"
		commit_id="d100e6cdd4c67cbe5322fa26b2ee8aa34ea7ebcf"
		git clone $repo_url
		(
			cd lcov || return 1
			git checkout $commit_id
			make install
		)
	fi

	if ! which lcov; then
		fail prepare "failed ot install lcov"
		exit
	fi

	# http://ltp.sourceforge.net/coverage/lcov/genhtml.1.php
	# Show yellow for >=25 < 50, green >= 50
	{
		echo "genhtml_med_limit = 25"
		echo "genhtml_hi_limit = 50"
		# Enable branch coverage
		echo "lcov_branch_coverage = 1"
	} >> /etc/lcovrc

	cki_upload_log_file "/etc/lcovrc"
}

if [ -n "$DEBUG" ]; then
	set -x
fi
