#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

source ../../../cki_lib/libcki.sh

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)
YUM=$(cki_get_yum_tool)
TNAME="storage/nvdimm/ndctl-test-suite"
RELEASE=$(uname -r | sed s/\.$(arch)//)
LINUX_RELEASE=$(echo $RELEASE | sed s/el8_[0-9]/el8/)
KERNEL="kernel-${RELEASE}"
DEVEL="kernel-devel-${RELEASE}"

function nvdimm_test_module_setup
{
	typeset pkg=$KERNEL
	typeset linux_srcdir="/root/rpmbuild/BUILD/$KERNEL/linux-$LINUX_RELEASE.$(arch)"
	if uname -r | grep -q 5.9; then
		linux_srcdir="/root/rpmbuild/BUILD/kernel-5.9/linux-$LINUX_RELEASE.$(arch)"
	fi
	typeset test_srcdir="$linux_srcdir/tools/testing/nvdimm"

	[ -d "$linux_srcdir" ] && rm -fr /root/rpmbuild
	rlRun "$YUM -y install $DEVEL"
	rlRun "$YUM download ${pkg} --source"
	typeset rpmfile=$(ls -1 ${pkg}.src.rpm)
	rlAssertExists "$rpmfile"
	if (($? != 0)); then
		rlLog "Abort test as kernel source rpm doesn't exists"
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi

	rlRun "rpm -ivh $rpmfile"
	rlRun "rpmbuild -bp --nodeps ~/rpmbuild/SPECS/kernel.spec"
	rlAssertExists "$linux_srcdir"
	rlAssertExists "$test_srcdir"
	if (($? != 0)); then
		rlLog "Abort test as kernel source doesn't exists after rpmbuild -bp"
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi

	rlRun "pushd $test_srcdir"
	rlRun "make -C /lib/modules/$(uname -r)/build M=$PWD"
	if (( $? != 0 )); then
		rlLog "Abort test as make under test dir failed"
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
		exit 1
	fi
	rlRun "make -C /lib/modules/$(uname -r)/build M=$PWD modules_install"
	if (( $? != 0 )); then
		rlLog "Abort test as make modules_install under test dir failed"
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi
	rlRun "popd"
}

function get_test_cases
{
	typeset testcases=""

	testcases+=" libndctl"
	testcases+=" dsm-fail"
	testcases+=" dpa-alloc"
	testcases+=" parent-uuid"
	testcases+=" multi-pmem"
	testcases+=" create.sh"
	testcases+=" clear.sh"
	testcases+=" pmem-errors.sh"
	testcases+=" daxdev-errors.sh"
	testcases+=" multi-dax.sh"
	testcases+=" btt-check.sh"
	testcases+=" label-compat.sh"
	testcases+=" blk-exhaust.sh"
	testcases+=" sector-mode.sh"
	testcases+=" inject-error.sh"
	testcases+=" btt-errors.sh"
	testcases+=" hugetlb"
	testcases+=" btt-pad-compat.sh"
	testcases+=" firmware-update.sh"
	testcases+=" ack-shutdown-count-set"
	testcases+=" rescan-partitions.sh"
	testcases+=" inject-smart.sh"
	testcases+=" monitor.sh"
	testcases+=" max_available_extent_ns.sh"
	testcases+=" pfn-meta-errors.sh"
	uname -r | grep -qE "4.18.0-147" || testcases+=" track-uuid.sh"

	echo $testcases
}


function ndctl_setup
{
	LOOKASIDE=https://github.com/yizhanglinux/ndctl.git

	[ -d ndctl ] &&	rm -rf ndctl
	rlRun "git clone $LOOKASIDE"
	rlRun "pushd ndctl"
	rlRun "./autogen.sh"
	rlRun "./configure CFLAGS='-g -O2' --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib64 --disable-docs --enable-test"
	if (( $? != 0 )); then
		rlLog "Abort test as ndctl setup failed"
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi
	rlRun "popd"
}

function get_timestamp
{
	date +"%Y-%m-%d %H:%M:%S"
}

function do_test
{
	export KVER=5.7
	typeset test_case=$1

	echo ">>> $(get_timestamp) | Start to run test case $test_case ..."
	rlRun "make TESTS=$test_case check"
	typeset -i ret=$?
	echo ">>> $(get_timestamp) | End: $test_case"

	if (( $ret == 0)); then
		rstrnt-report-result "ndctl test suite: $test_case" PASS 0
	else
		rstrnt-report-result "ndctl test suite: $test_case" FAIL 0
		rlFileSubmit "test/${test_case}.log"
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
	testcases=${_DEBUG_MODE_TESTCASES:-"$(echo $testcases_default)"}
	ret=0
	rlRun "pushd ndctl"
	for testcase in $testcases; do
		do_test $testcase
		((ret += $?))
	done

	if (( $ret != 0 )); then
		echo ">> There are failing tests, pls check it"
	fi
}

cki_main
