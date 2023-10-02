#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/memory/function/memkind
#   Description: Test memkind with upstream testsuite
#   Author: Li Wang <liwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/bin/rhts-environment.sh	  || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

OUTPUTFILE=${OUTPUTFILE:-/mnt/testarea/memkind/outputfile}
TASKID=${TASKID:-UNKNOWN}
NODES=$(numactl -H | grep available | cut -d ' ' -f 2)

PACKAGE="memkind"
TESTVERSION=${MKVERSION:-1.7.0}

# don't user root user by default, as there's some failures for permission
# issues.
USE_ROOT=${USE_ROOT:-1}

TESTAREA=/mnt/testarea
TARGET=${PACKAGE}-${TESTVERSION}
WORK_DIR=${TARGET}

function system_check()
{
	TESTSKIP=0
	local ARCH=$(uname -m)
	if [ ${ARCH} != "x86_64" ]; then
		echo "Now only test on X86_64 system arch" | tee -a $OUTPUTFILE
		TESTSKIP=1
	fi

	if [ $NODES -lt 2 ]; then
		echo "The NUMA NODES should be more than 2" |tee -a $OUTPUTFILE
		TESTSKIP=1
	fi

	if [ $TESTSKIP -eq 1 ]; then
		report_result Test_Skipped PASS 99
		exit 0
	fi
}

function run_test()
{
	r_test=$1
	testlog=${TESTAREA}/memkind_${r_test}.log

	# rpm is not needed for rhel as it's defined in rpm spec
	[ "$1" = rpm ] && return

	rlRun "make $r_test 2>&1 > $testlog"
	rlFileSubmit test-suite.log
	rlFileSubmit $testlog
}

function run_test_srpm()
{
	local arch=$(uname -m)
	local repo=http://download.devel.redhat.com/brewroot/packages/memkind
	local old_nu="$(cat /proc/sys/kernel/numa_balancing)"
	local old_tr="$(sed -n 's/.*\[\(.*\)\].*/\1/p' /sys/kernel/mm/transparent_hugepage/enabled)"

	test -f SRPM_DONE && return

	rlPhaseStartTest "testsuite-srpm"

	rpm -q memkind || rlRun "$yum_cmd -y install memkind"
	rpm -q memkind || { echo "failed to install memkind" && return 1; }

	if rlIsRHEL 8 || rlIsRHEL 9 || rlIsFedora; then
		local yum_cmd=dnf
		local yum_builddep="dnf builddep"
		version="${version:-$(rpm -q memkind --qf "%{version}")}"
		release="${release:-$(rpm -q memkind --qf "%{release}")}"
		rlRun "$yum_cmd -y install numactl python2-pytest.noarch bc"
		# For py-test hack
		! test -f /usr/bin/py.test && rlRun "ln -s /usr/bin/py.test-2 /usr/bin/py.test"
	else
		local yum_cmd=yum
		local yum_builddep="yum-builddep"
		version="${memkind_version:-1.7.0}"
		release="${memkind_release:-1.el7}"
		rlRun "yum -y install pytest"
	fi

	# For emulate slow memory, this is related numa topology, sometimes it may generate
	# bad effect that make some failures.
	export MEMKIND_HBW_NODES=1

	if ((USE_ROOT)); then
		c_folder="true"
		r_folder="true"
		spec_path=/root/rpmbuild/SPECS
		src_folder=/root/rpmbuild/BUILD/memkind-$version
	else
		c_folder="pushd /home/test"
		r_folder="popd"
		su_str="su test"
		spec_path=/home/test/rpmbuild/SPECS
		src_folder=/home/test/rpmbuild/BUILD/memkind-$version
		mkdir -p /home/test/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
		echo '%_topdir %(echo $HOME)/rpmbuild' > /home/test/.rpmmacros
	fi

	# The first change folder to the $HOME
	$c_folder

	rlRun "wget ${repo}/${version}/${release}/src/memkind-${version}-${release}.src.rpm"
	rlRun "wget ${repo}/$version/$release/$arch/memkind-${version}-${release}.${arch}.rpm"
	rlRun "$su_str bash -c \"rpm -ivh memkind-${version}-${release}.src.rpm\""


	local tree_version=$(rpm -q --qf "%{VERSION}" memkind)
	local tree_release=$(rpm -q --qf "%{RELEASE}" memkind)

	if [ "$(echo ${version//./} \> ${tree_version//./} | bc)" = 1 ]; then
		upgrade=" -Uvh"
	elif [ "$(echo ${version//./} == ${tree_version//./} | bc)" = 1 ] && [ "$(echo ${release%.*} \> ${tree_release%.*} | bc)" = 1 ]; then
		upgrade=" -Uvh"
	elif [ "${version}${release}" = "${tree_version}${tree_release}" ]; then
		rlLogInfo "Using in-tree memkind $(rpm -q memknid) for testing"
		upgrade=""
	else
		upgrade=" -Uvh --oldpackage "
		[ -z "$memkind_version" -o -z "$memkind_release" ] && rlDie "The memkind $(rpm -q memkind) needs upgrade!"
	fi
	chown -R test:test  /home/test
	[ -n "$upgrade" ] && rlRun "rpm $upgrade memkind-${version}-${release}.${arch}.rpm"
	rlRun "bash -c \"$yum_builddep -y $spec_path/memkind.spec\""
	rlRun "$su_str bash -c \"rpmbuild -bp $spec_path/memkind.spec\""

	# patches need to verify.
	local patchdir=$(pwd)/patches/
	local test_patch=workaround-memkind-test-node.patch

	# The seocnd change folder to the rpmbuild src folder
	pushd $src_folder

	# Apply patch to verify it.
	pushd test
	patch < $patchdir/$test_patch
	popd

	local version_maj=$(echo $version | cut -d. -f 1)
	local version_min=$(echo $version | cut -d. -f 2)

	export JE_PREFIX=jemk_
	if [ "$(echo ${version_maj}.${version_min} \>= 1.10 | bc)" = 1 ]; then
		rlRun "./autogen.sh"
		rlRun "./configure"
		rlRun "make"
		rlRun "make install"
	else
		rlRun "$su_str bash -c ./build_jemalloc.sh" || { echo "build jemalloc failed" && return 1; }
		rlRun "$su_str bash -c ./build.sh" || { echo "build memkind failed" && return 1; }
	fi

	bash -c "ln -s $(which memkind-hbw-nodes) test/python_framework/"

	# For Dlopen test to find the expected share object (libmemkind.so)
	! test -f /usr/lib64/libmemkind.so && rlRun "ln /usr/lib64/libmemkind.so.0 /usr/lib64/libmemkind.so -s"
	rlRun "echo 0 > /proc/sys/kernel/numa_balancing"

	# For avoid cache footprint
	rlRun "echo never > /sys/kernel/mm/transparent_hugepage/enabled"

	if ((USE_ROOT)); then
		rlRun "make check"
	else
		rlLog "Using test user to do the test ..."
		rlRun "chown -R test:test /home/test"
		rlRun "su test bash -c 'make check'"
	fi
	cp test-suite.log test-suite-srpm.log
	rlFileSubmit "test-suite-srpm.log"

	popd
	$r_folder

	rlRun "echo $old_nu > /proc/sys/kernel/numa_balancing"
	rlRun "echo $old_tr > /sys/kernel/mm/transparent_hugepage/enabled"

	rlPhaseEnd

	touch SRPM_DONE
}

function rerun_failed_tests()
{
	local i=0
	local j
	local f

	rlRun -l "grep -i failed test-suite.log" 0-255
	echo =========================[$((i++))]===================
	for f in $(grep -i failed test-suite.log  | awk -F, '{print $1}'); do
		for j in $(seq 10); do
			./test/test.sh -f $f | tee retest-failed-${f}.log
			! grep -i failed  retest-failed-${f}.log && break
		done
		if grep -i failed retest-failed-${f}.log; then
			rlReport "re-test $f $j" FAIL 250 retest-failed-${f}.log
		else
			rlReport "re-test $f $j" PASS 0 retest-failed-${f}.log
		fi
	done
}

# ------ Start Testing ------

rlJournalStart
	rlPhaseStartSetup
		# increase our chances of getting huge pages
		rlRun "system_check"
		#rlRun "pushd ${WORK_DIR}" 0
	rlPhaseEnd

	run_test_srpm

	rlPhaseStartTest "retest failed tests"
		pushd $src_folder
		rerun_failed_tests
		popd
	rlPhaseEnd

	#rlPhaseStartTest "check"
	#	rlRun "run_test check"
	#rlPhaseEnd

	#rlPhaseStartTest "rpm"
	#	rlRun "run_test rpm"
	#rlPhaseEnd

	rlPhaseStartCleanup
	rlRun "popd" 0
	rlPhaseEnd
rlJournalEnd
