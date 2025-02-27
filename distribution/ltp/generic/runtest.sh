#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

. ../../../cki_lib/libcki.sh || exit 1
. ../include-ng/include.sh   || exit 1

function fetch_testcase()
{
	if [ "$TESTARGS" ]; then
		# We can specify lists of tests to run. If the list file provided,
		# copy/replace it. For example, we can provide a customized list of
		# tests in `RHEL6KT1LITE', Then, we can set TESTARGS="RHEL6KT1LITE"
		echo " ========== TESTARGS given, start test ==========="
		for file in $TESTARGS; do
			if [ -f "$file" ]; then
				cp "$file" $LTPDIR/runtest/
			elif [ -f "configs/$file" ]; then
				cp "configs/$file" $LTPDIR/runtest/
			else
				echo "$file not found." | tee -a $OUTPUTFILE
			fi
		done
		TESTS=$TESTARGS
	else
		# Default lists of tests to run.
		echo " ========== execute default testcases ============"
		TESTS='syscalls can cve commands fs math mm numa nptl pty sched ipc tracing dio'
	fi
}

function knownissue_handle()
{
	case $SKIP_LEVEL in
	   "0")
		knownissue_exclude "none"  $LTPDIR/runtest/*
		;;
	   "1")
		knownissue_exclude "fatal"   $LTPDIR/runtest/*
		;;
	     *)
		# skip all the issues by default
		knownissue_exclude "all" $LTPDIR/runtest/*
		;;
	esac
}

function set_filesystem()
{
	# if FSTYP is set, we're testing filesystem, enable fs related requirements
	# to get larger test coverage and test the correct fs.
	# overlayfs is special, no mkfs.overlayfs is available, and tests need LTP_DEV
	# is not designed for overlayfs, so they can be skipped
	if [ -n "$FSTYP" ] && [ "$FSTYP" != "overlayfs" ]; then
		# prepare test device for fs tests and pass it to RunTest()
		LOOP_IMG=ltp-$FSTYP.img
		dd if=/dev/zero of=$LOOP_IMG bs=1M count=1024
		LOOP_DEV=`losetup -f`
		losetup $LOOP_DEV $LOOP_IMG
		export LTP_DEV=$LOOP_DEV
		export LTP_DEV_FS_TYPE=$FSTYP
		export LTP_BIG_DEV=$LOOP_DEV
		export LTP_BIG_DEV_FS_TYPE=$FSTYP
		OPTS="$OPTS -b $LTP_DEV -B $LTP_DEV_FS_TYPE -z $LTP_BIG_DEV -Z $LTP_BIG_DEV_FS_TYPE"
	fi
}

function set_timeout_mul()
{
	# Some tasks may fail on slower machines with:
	#   tst_test.c:984: INFO: If you are running on slow machine, try
	#   exporting LTP_TIMEOUT_MUL > 1
	#   tst_test.c:985: BROK: Test killed! (timeout?)
	# So we define LTP_TIMEOUT_MUL=2 to avoid these failures and have the
	# option to override it with Beaker parameters.
	export LTP_TIMEOUT_MUL=2
	if [ -n "$TIMEOUT_MUL" ]; then
		export LTP_TIMEOUT_MUL=${TIMEOUT_MUL}
	fi
}

function audit_rule_setting()
{
	# To mask the AVC denied warning from SELinux
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1701
	auditctl -a always,exclude -F exe=/mnt/testarea/ltp/testcases/bin/fanotify14 -F msgtype=AVC
}

function audit_rule_delete()
{
	auditctl -d always,exclude -F exe=/mnt/testarea/ltp/testcases/bin/fanotify14 -F msgtype=AVC
}

function ltp_test_begin()
{
	# disable NTP and chronyd
	tservice=""
	pgrep chronyd > /dev/null
	if [ $? -eq 0 ]; then
		tservice="chronyd"
		service chronyd stop
	fi
	DisableNTP

	echo "ulimit -c unlimited"
	ulimit -c unlimited

	PrintSysInfo

	build_all
	fetch_testcase
	knownissue_handle
	skip_testcase
	set_filesystem
	set_timeout_mul
	audit_rule_setting
}

function ltp_test_run()
{
	RunFiltTest && return

	for t in $TESTS; do
		rm -f /mnt/testarea/$t.*
		rm -f /mnt/testarea/ltp/output/*
		CleanUp $t

		OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`
		RunTest $t "$OPTS"
	done
}

function ltp_test_end()
{
	audit_rule_delete

	# restore either NTP or chronyd
	if [ -n "$tservice" ]; then
		service chronyd start
	else
		EnableNTP
	fi

	SubmitLog $DEBUGLOG

	if [ -n "$LTP_DEV" ]; then
		losetup -d $LOOP_DEV
		rm -f $LOOP_IMG
	fi
}

# ---------- Start Test -------------
[ -z "${REBOOTCOUNT##*[!0-9]*}" ] && REBOOTCOUNT=0
if [ "${REBOOTCOUNT}" -ge 1 ]; then
	echo "===== Test has already been run, \
	Check logs for possible failures ======"
	rstrnt-report-result CHECKLOGS FAIL 99
	exit 0
fi

# Sometimes it takes too long to waiting
# for syscalls finish and I want to know
# whether the compilation is finish or not
rstrnt-report-result "install" "PASS"

ltp_test_begin

ltp_test_run

ltp_test_end

exit 0
