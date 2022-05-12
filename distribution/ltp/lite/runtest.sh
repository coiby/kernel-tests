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
if  cki_is_vm; then
    export LTP_TIMEOUT_MUL=2
fi

# debug kernel is slower increase LTP_TIMEOUT_MUL
if  cki_is_kernel_debug; then
    export LTP_TIMEOUT_MUL=2
fi

core_pattern="$(cat /proc/sys/kernel/core_pattern)"
core_pattern_ltp_dir="/mnt/testarea/ltp/cores"

# RHELKT1LITE is the default set of tests to run for RHEL builds
RUNTESTS=${RUNTESTS:-""}

PATCHDIR=$(dirname ${BASH_SOURCE[0]})"/patches"

function ltp_test_build()
{
	cp -vf configs/RHELKT1LITE.${TESTVERSION} RHELKT1LITE
	if [ $? -ne 0 ]; then
		echo "FAIL: couldn't copy configs/RHELKT1LITE.${TESTVERSION}"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
	fi
	# The test could be running on different path
	# Just skip the build, but make sure the config is copied
	if [ -f ${LTPDIR}/runltp ]; then
		echo "LTP has been built and installed!"
		return
	fi

	build-all
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
}

function runtest_prepare()
{
	# Doesn't matter the RUNTEST save logs with same name
	# to make easier triaging issues
	t="RHELKT1LITE.FILTERED"
	local runtest_path=$LTPDIR/runtest
	local runtest=$runtest_path/$t
	if [[ -z "${RUNTESTS}"  ]]; then
		cp -f RHELKT1LITE "$runtest"
	else
		rm -f "$runtest"
		for RUNTEST in ${RUNTESTS}; do
			echo "Using ${RUNTEST} as base for $runtest"
			# get the test names used on defined on $RUNTEST
			if [[ ! -e $runtest_path/${RUNTEST} ]]; then
				echo "skipping runtest ${RUNTEST}, because it doesn't exist"
				continue
			fi
			local tests=$(cat $runtest_path/${RUNTEST} | grep -vE "^#|^$" | awk '{print$1}')
			# from the possible tests, only uses tests configured/enabled on RHELKT1LITE
			for test in $tests; do
				grep "^$test\>" RHELKT1LITE >> "$runtest"
			done
		done
		if [ ! -s $runtest ]; then
			echo "skipping as no test is available for '${RUNTESTS}'"
			rstrnt-report-result "${RSTRNT_TASKNAME}" SKIP
			exit 0
		fi
	fi

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
}

function ltp_lite_begin()
{
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

	runtest_prepare

	echo "ulimit -c unlimited" | tee -a $OUTPUTFILE
	ulimit -c unlimited
	mkdir -p $core_pattern_ltp_dir
	echo "$core_pattern_ltp_dir/core" > /proc/sys/kernel/core_pattern
	echo 1 > /proc/sys/kernel/core_uses_pid

	echo "Using config file: $t" | tee -a $OUTPUTFILE
	ss -antup >> $OUTPUTFILE 2>&1

	cp -f $OUTPUTFILE ./setup.txt
	SubmitLog ./setup.txt

	PrintSysInfo
}

ltp_lite_run()
{
	RunFiltTest && return

	rm -f /mnt/testarea/$t.*
	rm -f /mnt/testarea/ltp/output/*
	CleanUp $t

	OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`
	service cgconfig stop

	RunTest $t
}

ltp_lite_end()
{
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
	rstrnt-report-result CHECKLOGS FAIL 99
	exit 0
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
rstrnt-report-result "install" PASS

ltp_lite_begin

ltp_lite_run

ltp_lite_end

if [ "$result_r" = "PASS" ]; then
       exit 0
else
       exit 1
fi
