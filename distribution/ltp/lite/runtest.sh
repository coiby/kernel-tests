#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

. ../../../cki_lib/libcki.sh || exit 1
. ../include/runtest.sh      || exit 1
. ../include/knownissue.sh   || exit 1
. ../include/ltp-make.sh     || exit 1

#export AVC_ERROR=+no_avc_check
#export RHTS_OPTION_STRONGER_AVC=

# VMs can have slow performance, therefore increase LTP_TIMEOUT_MUL
if cki_is_vm; then
	export LTP_TIMEOUT_MUL=${LTP_TIMEOUT_MUL:-2}
	export LTP_RUNTIME_MUL=${LTP_RUNTIME_MUL:-5}
fi

# debug kernel is slower increase LTP_TIMEOUT_MUL
if cki_is_kernel_debug; then
	export LTP_TIMEOUT_MUL=${LTP_TIMEOUT_MUL:-2}
	export LTP_RUNTIME_MUL=${LTP_RUNTIME_MUL:-5}
fi

[ -n "${LTP_TIMEOUT_MUL}" ] && echo "LTP_TIMEOUT_MUL is ${LTP_TIMEOUT_MUL}"
[ -n "${LTP_RUNTIME_MUL}" ] && echo "LTP_RUNTIME_MUL is ${LTP_RUNTIME_MUL}"

core_pattern="$(cat /proc/sys/kernel/core_pattern)"
core_pattern_ltp_dir="/mnt/testarea/ltp/cores"
runtest_path=$LTPDIR/runtest

# RHELKT1LITE is the default set of tests to run for RHEL builds
RUNTESTS=${RUNTESTS:-"RHELKT1LITE"}

PATCHDIR=$(dirname ${BASH_SOURCE[0]})"/patches"

function ltp_test_build()
{
	# The test could be running on different path
	# Just skip the build, but make sure the config is copied
	if [[ ! -f ${LTPDIR}/runltp ]] || ! grep -q "${TESTVERSION}" ${TARGET_DIR}/ltp_version; then
		build-all
	fi
	if [[ -z ${LTP_COMMIT_ID} ]]; then
		RHELKT1LITE_CONFIG=RHELKT1LITE.${TESTVERSION}
	else
		RHELKT1LITE_CONFIG=RHELKT1LITE.next
	fi
	cp -vf configs/${RHELKT1LITE_CONFIG} ${runtest_path}/RHELKT1LITE
	if [ $? -ne 0 ]; then
		echo "FAIL: couldn't copy configs/${RHELKT1LITE_CONFIG}"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
	fi

	echo "LTP ($TESTVERSION) has been built and installed at ${LTPDIR}/runltp"
}


# prepare_aiodio_scratchspace
# exports:
#   SCRATCH_MNT
#   BIG_FILE
#   BUF_ALIGN
function prepare_aiodio_scratchspace()
{
	export SCRATCH_MNT=/mnt/scratchspace
	echo "Preparing scratchspace at: $SCRATCH_MNT" | tee -a $OUTPUTFILE
	if [ ! -e $SCRATCH_MNT ]; then
		echo "Creating $SCRATCH_MNT"           | tee -a $OUTPUTFILE
		mkdir $SCRATCH_MNT
	fi

	mkdir -p $SCRATCH_MNT/aiodio/junkdir
	export BIG_FILE="$SCRATCH_MNT/bigfile"

	block_size=0
	mntpoint=`df "$SCRATCH_MNT" | tail -n +2 | head -1 | cut -d ' ' -f1`
	if [ -n "$mntpoint" ]; then
		block_size=`blockdev --getbsz $mntpoint`
		echo "$SCRATCH_MNT's mount point is: $mntpoint" | tee -a $OUTPUTFILE
		echo "$mntpoint's block size is: $block_size"   | tee -a $OUTPUTFILE
	fi
	if [ "$block_size" -ge 512 ]; then
		export BUF_ALIGN=$block_size
	else
		export BUF_ALIGN=4096
	fi

	echo "SCRATCH_MNT: $SCRATCH_MNT" | tee -a $OUTPUTFILE
	echo "BIG_FILE:    $BIG_FILE"    | tee -a $OUTPUTFILE
	echo "BUF_ALIGN:   $BUF_ALIGN"   | tee -a $OUTPUTFILE
}

function clean_aiodio_scratchspace()
{
	rm -rf $SCRATCH_MNT/aiodio
}

function tolerate_s390_high_steal_time()
{
	local runtest=$1

	uname -m | grep -q s390
	if [ $? -ne 0 ]; then
		return
	fi

	sed -i 's/nanosleep01 nanosleep01/nanosleep01 timeout 300 sh -c "nanosleep01 || true"/' "$runtest"
	sed -i 's/clock_nanosleep01 clock_nanosleep01/clock_nanosleep01 timeout 300 sh -c "clock_nanosleep01 || true"/' "$runtest"
	sed -i 's/clock_nanosleep02 clock_nanosleep02/clock_nanosleep02 timeout 300 sh -c "clock_nanosleep02 || true"/' "$runtest"
	sed -i 's/futex_wait_bitset01 futex_wait_bitset01/futex_wait_bitset01 timeout 30 sh -c "futex_wait_bitset01 || true"/' "$runtest"
	sed -i 's/futex_wait05 futex_wait05/futex_wait05 timeout 30 sh -c "futex_wait05 || true"/' "$runtest"
	sed -i 's/epoll_pwait01 epoll_pwait01/epoll_pwait01 timeout 30 sh -c "epoll_pwait01 || true"/' "$runtest"
	sed -i 's/poll02 poll02/poll02 timeout 30 sh -c "poll02 || true"/' "$runtest"
	sed -i 's/pselect01 pselect01/pselect01 timeout 30 sh -c "pselect01 || true"/' "$runtest"
	sed -i 's/pselect01_64 pselect01_64/pselect01_64 timeout 30 sh -c "pselect01_64 || true"/' "$runtest"
	sed -i 's/select04 select04/select04 timeout 30 sh -c "select04 || true"/' "$runtest"
}

function exclude_disruptive_for_kt1()
{
	local runtest=$1

	if is_rhel7; then
		if [ "$osver" -le 705 ]; then
			# Bug 1261799 - ltp/oom1 cause the system hang
			sed -i 's/oom01 oom01/#DISABLED oom01 oom01/' "$runtest"
			sed -i 's/oom02 oom02/#DISABLED oom02 oom02/' "$runtest"

			# Bug 1223391 OOM sporadically triggers when process tries to malloc and dirty 80% of RAM+swap
			sed -i 's/mtest01w mtest01 -p80 -w/mtest01w sh -c "mtest01 -p80 -w || true"/' "$runtest"
		fi
	fi

	if cki_is_vm || cki_is_kernel_debug; then
		# fork13 takes 1 hour on vm or on debug kernel, quite too long for KT1 test
		sed -i 's/fork13 fork13/#DISABLED fork13 fork13/' "$runtest"
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

function runtest_prepare()
{
	local runtest_config=$1
	if [[ -z "${runtest_config}"  ]]; then
		echo "FAIL: no runtest conig was passed as argument to runtest_prepare"
		exit 1
	fi
	if [[ ! -s "${runtest_path}/${runtest_config}" ]]; then
		echo "FAIL: ${runtest_config} doesn't exit on ${runtest_path}"
		ls ${runtest_path}
		exit 1
	fi
	cp "${runtest_path}/${runtest_config}" "${runtest_path}/${runtest_config}.FILTERED"
	local runtest="$runtest_path/${runtest_config}.FILTERED"
	echo "Using config file: $runtest" | tee -a $OUTPUTFILE

	case $SKIP_LEVEL in
	   "0")
		knownissue_exclude  "none"  "$runtest"
		;;
	   "1")
		knownissue_exclude  "fatal" "$runtest"
		;;
	     *)
		# skip all the issues by default
		knownissue_exclude  "all"   "$runtest"
		;;
	esac

	tolerate_s390_high_steal_time "$runtest"

	exclude_disruptive_for_kt1 "$runtest"

	skip_testcase
}

function ltp_lite_begin()
{
	audit_rule_setting

	# disable NTP and chronyd
	tservice=""
	pgrep chronyd > /dev/null
	if [ $? -eq 0 ]; then
		tservice="chronyd"
		service chronyd stop
	fi
	DisableNTP

	# make sure there's enough entropy for getrandom tests
	rngd -r /dev/urandom

	prepare_aiodio_scratchspace


	echo "ulimit -c unlimited" | tee -a $OUTPUTFILE
	ulimit -c unlimited
	mkdir -p $core_pattern_ltp_dir
	echo "$core_pattern_ltp_dir/core" > /proc/sys/kernel/core_pattern
	echo 1 > /proc/sys/kernel/core_uses_pid

	ss -antup >> $OUTPUTFILE 2>&1

	cp -f $OUTPUTFILE ./setup.txt
	SubmitLog ./setup.txt

	PrintSysInfo
}

ltp_lite_run()
{
	for RUNTEST in $RUNTESTS; do
		RunFiltTest && return

		rm -f /mnt/testarea/$RUNTEST.*
		rm -f /mnt/testarea/ltp/output/*
		CleanUp $RUNTEST

		OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`
		service cgconfig stop
		runtest_prepare $RUNTEST
		# runtest_prepare created the $RUNTEST.FILTERED
		RunTest $RUNTEST.FILTERED "$OPTS"
	done
}

ltp_lite_end()
{
	audit_rule_delete

	echo "$core_pattern" > /proc/sys/kernel/core_pattern

	clean_aiodio_scratchspace

	# restore either NTP or chronyd
	if [ -n "$tservice" ]; then
		service chronyd start
	else
		EnableNTP
	fi

	bash ./grab_corefiles.sh >> $DEBUGLOG 2>&1
	SubmitLog $DEBUGLOG
}


# Build ltp test
ltp_test_build

# ---------- Start Test -------------
if [ "${RSTRNT_REBOOTCOUNT}" -ge 1 ]; then
	echo "===== Test has already been run,
	Check logs for possible failures ======"
	# This can happen, for example, if hit a kernel panic
	# the panic message might have been saved on journal
	if type -p journalctl > /dev/null; then
		JOURNALCTLLOG=/tmp/journalctl.log
		journalctl > "${JOURNALCTLLOG}"
		SubmitLog "${JOURNALCTLLOG}"
	fi
	rstrnt-report-result Abnormal-Reboot FAIL 99
	exit 0
fi

if type -p journalctl > /dev/null; then
	# if /var/log/journal doesn't exist create it to make logs persistent
	if [ ! -d /var/log/journal ]; then
		echo "INFO: enabling persistent storage for journalctl"
		mkdir -p /var/log/journal
		journalctl --flush
	fi
fi

# report patch errors from ltp/include
grep -i -e "FAIL" -e "ERROR" patchinc.log > /dev/null 2>&1
if [ $? -eq 0 ]; then
	rstrnt-report-result "ltp-include-patch-errors" WARN/ABORTED
	rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
fi

# Sometimes it takes too long to waiting for syscalls
# finish and I want to know whether the compilation is
# finish or not.
rstrnt-report-result "install (ltp-$TESTVERSION)" PASS

ltp_lite_begin

ltp_lite_run

ltp_lite_end

# if running as restraint job, the test result is already reported as subtests
# don't exit with values different of 0. Otherwise, restraint reports it as a separate subtest
if ! [[ -v RSTRNT_TASKID ]]; then
	if [ "$result_r" = "PASS" ]; then
		exit 0
	else
		exit 1
	fi
fi