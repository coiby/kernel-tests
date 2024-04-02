#!/bin/bash

source ../../../cki_lib/libcki.sh

FILE=$(readlink -f "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
NAME=$(basename "$FILE")
CDIR=$(dirname "$FILE")
YUM=$(cki_get_yum_tool)
# shellcheck disable=SC2034
TNAME="storage/nvdimm/ndctl-test-suite"
RELEASE="$(uname -r | sed s/\."$(arch)"//)"
KERNEL="kernel-${RELEASE}"
DEVEL="kernel-devel-${RELEASE}"

function nvdimm_test_module_setup
{
	typeset pkg=$KERNEL
	[ -d "/root/rpmbuild" ] && rm -fr /root/rpmbuild
	rlRun "$YUM -y install $DEVEL"
	rlRun "$YUM download $pkg --source"
	# shellcheck disable=SC2155
	typeset rpmfile="$(ls -1 "${pkg}".src.rpm)"
	rlAssertExists "$rpmfile"
	ret=$?
	if (( ret != 0)); then
		rlLog "Abort test as kernel source rpm doesn't exists"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi

	rlRun "rpm -ivh $rpmfile"
	rlRun "rpmbuild -bp --nodeps ~/rpmbuild/SPECS/kernel.spec"
	srcdir=$(realpath /root/rpmbuild/BUILD/kernel-*/linux-*)
	test_srcdir="$srcdir/tools/testing/nvdimm"
	rlAssertExists "$srcdir"
	rlAssertExists "$test_srcdir"
	ret=$?
	if ((ret != 0)); then
		rlLog "Abort test as kernel source doesn't exists after rpmbuild -bp"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi

	#RHEL9 need revert one patch to make compiling pass
	if rlIsRHEL 9 || rlIsCentOS 9 || rlIsFedora; then
		rlRun "cp revert.patch $srcdir"
		rlRun "pushd $srcdir"
		rlRun "patch -p1 < revert.patch"
	fi
	rlRun "pushd $test_srcdir"
	rlRun "make -C /lib/modules/$(uname -r)/build M=$PWD"
	ret=$?
	if (( ret != 0 )); then
		rlLog "Abort test as make under test dir failed"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
		exit 1
	fi
	rlRun "make -C /lib/modules/$(uname -r)/build M=$PWD modules_install"
	ret=$?
	if (( ret != 0 )); then
		rlLog "Abort test as make modules_install under test dir failed"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi
	rlRun "popd"
}

function get_test_cases
{
	typeset testcases=""

	testcases+=" libndctl"
	testcases+=" dsm-fail"
	uname -r | grep -q "4.18.0" || testcases+=" dpa-alloc"
	uname -r | grep -q "4.18.0" || testcases+=" parent-uuid"
	uname -r | grep -q "4.18.0" || testcases+=" multi-pmem"
	testcases+=" create.sh"
	testcases+=" clear.sh"
	testcases+=" pmem-errors.sh"
	testcases+=" daxdev-errors.sh"
	testcases+=" multi-dax.sh"
	testcases+=" btt-check.sh"
	testcases+=" label-compat.sh"
	uname -r | grep -q "4.18.0" || testcases+=" blk-exhaust.sh"
	testcases+=" sector-mode.sh"
	testcases+=" inject-error.sh"
	testcases+=" btt-errors.sh"
	testcases+=" hugetlb"
	testcases+=" btt-pad-compat.sh"
	lsmod | grep -q e1000e || testcases+=" firmware-update.sh"  #BZ2123263
	testcases+=" ack-shutdown-count-set"
	testcases+=" rescan-partitions.sh"
	uname -r | grep -qE "el9_0|el9_1|el9_2" || testcases+=" inject-smart.sh" #BZ2048105
	testcases+=" monitor.sh"
	testcases+=" max_available_extent_ns.sh"
	testcases+=" pfn-meta-errors.sh"
	uname -r | grep -qE "4.18.0-147|4.18.0-193|4.18.0-240" || testcases+=" track-uuid.sh"

	echo "$testcases"
}


function ndctl_setup
{
	pushd "$CDIR" || return 1
	rlRun "$YUM download ndctl --source"
	# shellcheck disable=SC2155
	typeset rpmfile="$(ls -1 ndctl*.src.rpm)"
	rlAssertExists "$rpmfile"
	ret=$?
	if ((ret != 0)); then
		rlLog "Abort test as ndctl source rpm doesn't exists"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi
	rlRun "rpm -ivh $rpmfile"
	rlRun "rpmbuild -bp ~/rpmbuild/SPECS/ndctl.spec"
	ndctl_srcdir=$(realpath /root/rpmbuild/BUILD/ndctl-*)
	rlRun "pushd $ndctl_srcdir"

	if rlIsRHEL ">9.1" || rlIsFedora || rlIsCentOS "9"; then
		lsmod | grep -q e1000e && rlRun "sed -i \"/firmware-update.sh/d\" test/meson.build"
		rlRun "patch -p1 < $CDIR/ndctl.patch"
		rlRun "yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
		rlRun "yum -y install asciidoctor"
		rlRun "meson setup build"
		rlRun "meson compile -C build"
	else
		rlRun "./autogen.sh"
		rlRun "./configure CFLAGS='-g -O2' --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib64 --disable-docs --enable-test"
	fi
	ret=$?
	if (( ret != 0 )); then
		rlLog "Abort test as ndctl setup failed"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi
}

function get_timestamp
{
	date +"%Y-%m-%d %H:%M:%S"
}

function do_test
{
	export KVER=6.0.0
	typeset test_case=$1

	echo "Start: ndctl test suite: $test_case" >/dev/kmsg
	echo ">>> $(get_timestamp) | Start to run test case $test_case ..."
	rlRun "make TESTS=$test_case check"
	typeset -i ret=$?
	echo ">>> $(get_timestamp) | End: $test_case"
	echo "End: ndctl test suite: $test_case" >/dev/kmsg

	if (( ret == 0)); then
		rstrnt-report-result "ndctl test suite: $test_case" PASS
	else
		rstrnt-report-result "ndctl test suite: $test_case" FAIL
		cki_upload_log_file "test/${test_case}.log"
	fi

	return $ret
}

function startup
{
	nvdimm_test_module_setup
	ndctl_setup
}

function runtest
{
	testcases_default=""
	testcases_default+=" $(get_test_cases)"
	testcases="${_DEBUG_MODE_TESTCASES:-"$testcases_default"}"
	local ret=0
	rlRun "pushd $ndctl_srcdir"
	if rlIsRHEL ">9.1" || rlIsFedora || rlIsCentOS "9"; then
		echo "Start: ndctl test suite" >/dev/kmsg
		rlRun "meson test -C build --no-suite cxl"
		ret=$?
		if (( ret == 0)); then
			rstrnt-report-result "ndctl test suite" PASS
		else
			rstrnt-report-result "ndctl test suite" FAIL
		fi
		echo "End: ndctl test suite" >/dev/kmsg
		cki_upload_log_file "$ndctl_srcdir/build/meson-logs/testlog.txt"
	else
		for testcase in $testcases; do
			do_test "$testcase"
			((ret += $?))
		done
	fi
	if (( ret != 0 )); then
		echo ">> There are failing tests, pls check it"
	fi
}

# shellcheck disable=SC2119
cki_main
