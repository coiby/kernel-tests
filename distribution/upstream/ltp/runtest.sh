#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2020 Red Hat, Inc.

. ../../../cki_lib/libcki.sh            || exit 1
. /usr/share/beakerlib/beakerlib.sh	|| exit 1
. ../include/runtest.sh			|| exit 1
. ../include/knownissue.sh		|| exit 1

# VMs can have slow performance, therefore increase LTP_TIMEOUT_MUL
cki_is_vm && export LTP_TIMEOUT_MUL=2

# debug kernel is slower increase LTP_TIMEOUT_MUL
# upstream kernels don't contain _debug on kernel name,
# check for common debug flag options
cki_has_kernel_debug_flags && export LTP_TIMEOUT_MUL=2

TARGET_DIR=/mnt/testarea/ltp
RUNTESTS=${RUNTESTS:-"cve sched syscalls can commands containers dio fs math hugetlb mm nptl pty tracing"}
CPUS_NUM=$(getconf _NPROCESSORS_ONLN || echo 1)
MEM_AVAILABLE=$(echo "$(grep '^MemAvailable:' /proc/meminfo | sed 's/^[^0-9]*\([0-9]*\).*/\1/') / 1024" |bc -q)

function test_msg()
{
	case $1 in
		pass) echo "PASS: $2" ;;
		warn) echo "WARN: $2" ;;
		fail) echo "FAIL: $2"; sleep 2 ;exit 1 ;;
		 log) echo "LOG : $2" ;;
		   *) echo "EXIT: Wrong parameters"; sleep 2; exit 2 ;;
	esac
}

# A recent commit in the upstream LTP repo that passes all travis checks
#
# NOTE: We use a tested commit to avoid that breakage in LTP's master branch
#       which may make our test suites less stable
LTP_COMMIT_ID=${LTP_COMMIT_ID:-"master"}
LTP_REPO_ADDR=${LTP_REPO_ADDR:-"https://github.com/linux-test-project/ltp"}
function ltp_test_build()
{
	# NOTE: Skip to built and install ltp if it is done as we split a
	#       single task to run LTP tests into multiple tasks. For more
	#       details, please refer to:
	#       o https://gitlab.com/redhat/centos-stream/tests/kernel/kpet-db/-/issues/54
	if [ -f ${LTPDIR}/runltp ] && grep -q "${LTP_COMMIT_ID}" ${LTPDIR}/ltp_version; then
		test_msg pass "LTP (${LTP_COMMIT_ID}) has been built and installed!"
		return
	fi

	# workaround for the beaker issue when arch is ppc64:
	# Makefile:495: /mnt/tests/kernel/distribution/upstream-kernel/install/linux/arch/ppc64/Makefile: No such file or directory
	if [[ ${ARCH} = ppc64 || ${ARCH} = ppc || ${ARCH} = s390x || ${ARCH} = s390 ]]; then
		unset ARCH
	fi

	if [ -f ltp/.git/config ]; then
		pushd ltp; git pull  > /dev/null 2>&1; popd
	else
		git clone $LTP_REPO_ADDR ltp \
		    > /dev/null 2>&1 || \
		    test_msg fail "git clone ltp upstream failed"
		test_msg pass "git clone LTP upstream"
	fi

	pushd ltp > /dev/null 2>&1
	git checkout $LTP_COMMIT_ID

	# Timing on systems with shared resources (and high steal time) is not accurate, apply patch for non bare-metal machines
	patch -p1 < ../patches/ltp-include-relax-timer-thresholds-for-non-baremetal.patch
	# Disable btrfs testing
	patch -p1 < ../patches/disable-btrfs.patch
	# more logs for issue 674
	patch -p1 < ../patches/more-logs-for-tst_find_backing_dev.patch
	# Debug patching temporarily (remove it after got the reason)
	git describe c4742ee0df03b > /dev/null 2>&1 || patch -p1 < ../patches/debug/0001-mkfs-print-more-info-for-debugging.patch

	make autotools                      &> configlog.txt || if cat configlog.txt; then test_msg fail "config  ltp failed"; fi
	./configure --prefix=${TARGET_DIR}  &> configlog.txt || if cat configlog.txt; then test_msg fail "config  ltp failed"; fi
	make -j$CPUS_NUM                    &> buildlog.txt  || if cat buildlog.txt;  then test_msg fail "build   ltp failed"; fi
	make install                        &> buildlog.txt  || if cat buildlog.txt;  then test_msg fail "install ltp failed"; fi
	popd > /dev/null 2>&1
	test_msg pass "LTP (${LTP_COMMIT_ID}) build/install successful"
	echo "${LTP_COMMIT_ID}" > ${LTPDIR}/ltp_version
}

function hugetlb_nr_setup()
{
	grep -q hugetlbfs /proc/filesystems || return
	echo 3 >/proc/sys/vm/drop_caches
	echo 1 >/proc/sys/vm/compact_memory

	cat hugetlb.inc > hugetlb

	mem_alloc=0
	hpagesize=$(echo `grep 'Hugepagesize:' /proc/meminfo | awk '{print $2}'` / 1024 | bc)

	test_msg log "Calculate memory to be reserved for hugepages" | tee -a ${OUTPUTFILE}
	[ $MEM_AVAILABLE -gt 512 ] && mem_alloc=512
	[ "${ARCH}" = "s390x" ] && [ $MEM_AVAILABLE -gt 128 ] && mem_alloc=128 # only allocate 128MB on s390x

	[ $mem_alloc -eq 0 ] && RUNTESTS=${RUNTESTS//hugetlb} &&
		test_msg log "Removing hugetlb test (Mem_Available is too low to test)" && return

	nr_hpage=$(echo $mem_alloc / $hpagesize | bc)
	sed -i "s/#nr_hpage#/$nr_hpage/g" hugetlb

	# hugemmap05 test is a little different
	mem_alloc_overcommit=$(echo $MEM_AVAILABLE / 10 | bc)
	# reserve mem_alloc_overcommit for hugepage_size = 512MB system(eg. rhel_alt aarch64)
	[ "$mem_alloc_overcommit" -gt "64" ] && [ "x${hpagesize}" != "x512" ] && mem_alloc_overcommit=64
	nr_hugemmap5=$(echo $mem_alloc_overcommit / $hpagesize | bc)
	sed -i "s/#size#/${nr_hugemmap5}/g" hugetlb

	# hugemmap06 need more than 255 hugepages
	nr_hugemmap6=$(echo $MEM_AVAILABLE / $hpagesize | bc)
	[ "$nr_hugemmap6" -lt "256" ] && sed -i "s/hugemmap06//g" hugetlb

	mv -f hugetlb $LTPDIR/runtest
}

function hugetlb_test_pre()
{
	low_mem_mode=0

	case $(uname -m) in
	"i*86" | "x86_64")
		# i*86|x86_64) HPSIZE=2M; 2M * 128 = 256MB, using 2G for x86(rhel8 min: 1.5G) limitaion
		[ $MEM_AVAILABLE -le 2048 ] && low_mem_mode=1 &&
			test_msg log "MEM_AVAILABLE is less than 2048MB, shift to low_mem_mode testing"
		;;
	"ppc64" | "ppc64le")
		# ppc64|ppc64le) HPSIZE=16M; 16M * 128 = 2048MB
		[ $MEM_AVAILABLE -le 2048 ] && low_mem_mode=1 &&
			test_msg log "MEM_AVAILABLE is less than 2048MB, shift to low_mem_mode testing"
		;;
	"s390x")
		# s390x) HPSIZE=1024K; 1M * 128 = 128MB
		[ $MEM_AVAILABLE -le 256 ] && low_mem_mode=1 &&
			test_msg log "MEM_AVAILABLE is less than 256MB, shift to low_mem_mode testing"
		;;
	"aarch64")
		# aarch64) HPSIZE=512M; 512M * 128 = 65536MB
		[ $MEM_AVAILABLE -le 65536 ] && low_mem_mode=1 &&
			test_msg log "MEM_AVAILABLE is less than 64GB, shift to low_mem_mode testing"
		;;
	esac

	[ $low_mem_mode -eq 1 ] && hugetlb_nr_setup
}

function is_baremetal()
{
	# system with shared resources
	# any s390x system
	(uname -m | grep -q s390) && return 1

	# any guest system, e.g. ppc64 guests
	(hostname | grep -q guest) && return 1

	# any ppc lpar
	(uname -m | grep -q ppc) && (hostname | grep "\-lp") && return 1

	if command -v virt-what >/dev/null; then
		hv=$(virt-what)
		[[ $? -eq 0 && "$hv" != "" ]] && return 1
	fi

	return 0
}

function runtest_tweaker()
{
	local runtest="$LTPDIR/runtest/*"

	# tolerate s390 high steal time
	if uname -m | grep -q s390; then
		sed -i 's/nanosleep01 nanosleep01/nanosleep01 timeout 300 sh -c "nanosleep01 || true"/' $runtest
		sed -i 's/clock_nanosleep01 clock_nanosleep01/clock_nanosleep01 timeout 300 sh -c "clock_nanosleep01 || true"/' $runtest
		sed -i 's/clock_nanosleep02 clock_nanosleep02/clock_nanosleep02 timeout 300 sh -c "clock_nanosleep02 || true"/' $runtest
		sed -i 's/futex_wait_bitset01 futex_wait_bitset01/futex_wait_bitset01 timeout 30 sh -c "futex_wait_bitset01 || true"/' $runtest
		sed -i 's/futex_wait05 futex_wait05/futex_wait05 timeout 30 sh -c "futex_wait05 || true"/' $runtest
		sed -i 's/epoll_pwait01 epoll_pwait01/epoll_pwait01 timeout 30 sh -c "epoll_pwait01 || true"/' $runtest
		sed -i 's/poll02 poll02/poll02 timeout 30 sh -c "poll02 || true"/' $runtest
		sed -i 's/pselect01 pselect01/pselect01 timeout 30 sh -c "pselect01 || true"/' $runtest
		sed -i 's/pselect01_64 pselect01_64/pselect01_64 timeout 30 sh -c "pselect01_64 || true"/' $runtest
		sed -i 's/select04 select04/select04 timeout 30 sh -c "select04 || true"/' $runtest
	fi

	# reduce fork13 iteration
	sed -i 's/fork13 fork13 -i 1000000/fork13 fork13 -i 10000/' $runtest

	# reduce the number of dio tests on VM
	if ! is_baremetal; then
		sed -i 's/^dio/#&/' $runtest
		sed -i 's/^#\(dio0[1-6]\)/\1/' $runtest
	fi

	#
	# reduce the number of dio tests on x86_64 if the available memory size
	# of SUT <= 4G. For defails, please refer to:
	#     https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/624
	#
	if [ $(uname -m) == "x86_64" ] &&
	   [ $MEM_AVAILABLE -le 4096 ]; then
		sed -i 's/^dio/#&/' $runtest
		sed -i 's/^#\(dio0[1-6]\)/\1/' $runtest
	fi
}

function knownissue_handle()
{
	case $SKIP_LEVEL in
	   "0")
		knownissue_exclude "none"  $LTPDIR/runtest/*
		;;
	   "2")
		knownissue_exclude "all"   $LTPDIR/runtest/*
		;;
	     *)
		# Skip the fatal cases by default
		knownissue_exclude "fatal" $LTPDIR/runtest/*
		;;
	esac
}

function ltp_test_pre()
{
	# disable NTP and chronyd
	tservice=""
	pgrep chronyd > /dev/null
	if [ $? -eq 0 ]; then
		tservice="chronyd"
		service chronyd stop || test_msg warn "chronyd stop failed"
	fi
	DisableNTP || test_msg warn "Disable NTP failed"

	ulimit -c unlimited && echo "ulimit -c unlimited"

	mpstat 90 | tee /dev/null > /dev/kmsg &

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
		export OPTS="$OPTS -b $LTP_DEV -B $LTP_DEV_FS_TYPE -z $LTP_BIG_DEV -Z $LTP_BIG_DEV_FS_TYPE"
	fi

	hugetlb_test_pre
	runtest_tweaker
	knownissue_handle
}

function ltp_test_run()
{
	for RUNTEST in $RUNTESTS; do
		CleanUp $RUNTEST

		OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`
		RunTest $RUNTEST ${LTPDIR}/KNOWNISSUE "$OPTS"
	done
}

function ltp_test_end()
{
	# restore either NTP or chronyd
	if [ -n "$tservice" ]; then
		service chronyd start || test_msg warn "chronyd start failed"
	else
		EnableNTP || test_msg warn "Enable NTP failed"
	fi

	kill -s SIGINT $(pidof mpstat)
	sleep 2
	kill -9 $(pidof mpstat)

	SubmitLog $DEBUGLOG
}

# ------- Test Start --------
[ -z "${RSTRNT_REBOOTCOUNT##*[!0-9]*}" ] && RSTRNT_REBOOTCOUNT=0
if [ "${RSTRNT_REBOOTCOUNT}" -ge 1 ]; then
	test_msg log "======= Test has already been run, Check logs for possible failures ========="
	rstrnt-report-result CHECKLOGS FAIL 99
	exit 0
fi

rlJournalStart

	rlPhaseStartSetup
		rlRun "ltp_test_build"
	rlPhaseEnd

	ltp_test_pre
	ltp_test_run

	rlPhaseStartCleanup
		rlRun "ltp_test_end"
	rlPhaseEnd

rlJournalEnd
