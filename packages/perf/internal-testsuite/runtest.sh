#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /tools/perf/Regression/internal-testsuite-cki
#   Description: internal-testsuite
#   Author: Michael Petlan <mpetlan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. ../../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Known failure on Mustangs, skip this test until BZ 1619305 is resolved
if type -p dmidecode >/dev/null ; then
	if dmidecode -t1 | grep -q 'Product Name:.*Mustang.*' ; then
		rstrnt-report-result $TEST SKIP
		exit
	fi
fi

PACKAGE="perf"

# configuration
PERFTESTS_ENABLE_DENYLIST=${PERFTESTS_ENABLE_DENYLIST:-0}

# hook, someone likes using "True" there, we like 1, 0 values more
if [ "$PERFTESTS_ENABLE_DENYLIST" = "true" ] || [ "$PERFTESTS_ENABLE_DENYLIST" = "True" ]; then
	PERFTESTS_ENABLE_DENYLIST=1
fi

check_allowlisted()
{
	HASH=`echo -n "$1" | sha1sum | awk '{print $1}'`
	MATCH=`cat allow.list | perl -pe 's/#.*$//' | perl -pe 's/#\s*$/ /' | grep $HASH`

	if [ -z "$VIRT" ]; then			# skip KVM whitelist if the system is no a KVM
		MATCH=`echo -n $MATCH | grep -v KVM`
	fi

	if [[ -z "$MATCH" ]]; then
		return 1;
	fi

	# need a for loop for multiple matches
	set -- $MATCH
	while [[ $1 != "" ]]
	do
		shift;	# skip the hash
		local denylist_arch=$1; shift
		local denylist_kernel_version_start=$1; shift
		local denylist_kernel_version_end=$1; shift
		# TODO fix checking/skipping the KVM flag

		grep -q -e "all" -e "$MY_ARCH," <<<"$denylist_arch" || continue
		K_Vercmp $KERNEL $denylist_kernel_version_start
		[[ $K_KVERCMP_RET -ge "0" ]] || continue
		K_Vercmp $KERNEL $denylist_kernel_version_end
		[[ $K_KVERCMP_RET -lt "0" ]] || continue
		return 0
	done

	return 1
}

prepare_allowlists()
{
	rlRun "cp allow.list $TmpDir/" 0 "ALLOWLIST: adding basic allowlist"
}

# K_Vercmp() returns one of the following values in the global K_KVERCMP_RET:
#   -1 if kernel version from argument $1 is older
#    0 if kernel version from argument $1 is the same as $2
#    1 if kernel version from argument $1 is newer
K_KVERCMP_RET=0 # NOT CURRENTLY WORKING FOR THE KERNEL SUB VERSION starting with 0 TODO FIX
function K_Vercmp ()
{
	local ver1=`echo $1 | sed 's/-/./'`
	local ver2=`echo $2 | sed 's/-/./'`

	local ret=0
	local i=1
	while [ 1 ]; do
		local digit1=`echo $ver1 | cut -d . -f $i`
		local digit2=`echo $ver2 | cut -d . -f $i`

		if [ -z "$digit1" ]; then
			if [ -z "$digit2" ]; then
				ret=0
				break
			else
				ret=-1
				break
			fi
		fi

		if [ -z "$digit2" ]; then
			ret=1
			break
		fi

		if [ "$digit1" != "$digit2" ]; then
			if [ "$digit1" -lt "$digit2" ]; then
				ret=-1
				break
			fi
			ret=1
			break
		fi

		i=$((i+1))
	done
	K_KVERCMP_RET=$ret
}

# return 0 when running kernel rt
is_kernel_rt()
{
	local kernel_name=$(uname -r)
	if [[ "$kernel_name" =~ "rt" ]]; then
		echo 0
	else
		echo 1
	fi
}

rlJournalStart
	rlPhaseStartSetup
		rlAssertRpm $PACKAGE
		rlCheckRpm python-perf || yum -y install python-perf
		rlCheckRpm python3-perf || yum -y install python3-perf
		export MY_ARCH=`arch`
		export KERNEL=`uname -r`
		export VIRT=`virt-what`
		# unset ARCH variable in case it is set to something
		# (wrongly set ARCH variable breaks LLVM tests!!)
		unset ARCH

		kernel_name=$(rpm -q --queryformat '%{name}\n' -qf "/boot/config-$(uname -r)" | sed 's/-core//')
		KERNEL_PKG_NAME="$kernel_name-$KERNEL"
		KERNEL_DEBUGINFO_PKG_NAME="$kernel_name-debuginfo-$KERNEL"

		# strip-off the "+debug" and "+64k" suffix if present
		export KERNEL_DEBUGINFO_PKG_NAME=${KERNEL_DEBUGINFO_PKG_NAME%[+.]*}
		export KERNEL_PKG_NAME=${KERNEL_PKG_NAME%[+.]*}

		if cki_is_kernel_automotive; then
			export KERNEL_PKG_NAME="kernel-automotive-$KERNEL"
			export KERNEL_DEBUGINFO_PKG_NAME="kernel-automotive-debuginfo-$KERNEL"
		fi

		rlLog "Variables:"
		rlLog "KERNEL = $KERNEL"
		rlLog "KERNEL_PKG_NAME = $KERNEL_PKG_NAME"
		rlLog "KERNEL_DEBUGINFO_PKG_NAME = $KERNEL_DEBUGINFO_PKG_NAME"
		rpmquery $KERNEL_DEBUGINFO_PKG_NAME
		if [ $? -ne 0 ]; then
			INSTALL_CMD="debuginfo-install -y"
			if cki_is_kernel_automotive; then
				INSTALL_CMD="rpm-ostree -A --idempotent --allow-inactive install"
			else
				# we need to install debuginfo for the proper kernel
				# but sometimes, debuginfo-install is not available!
				which debuginfo-install || rlRun "yum -y install yum-utils dnf-utils" 0 "Installing {yum,dnf}-utils (it has not been present)"
			fi
			rlRun "$INSTALL_CMD $KERNEL_DEBUGINFO_PKG_NAME" 0 "Installing ($KERNEL_DEBUGINFO_PKG_NAME) via ($INSTALL_CMD)"
		fi
		rpmquery $KERNEL_DEBUGINFO_PKG_NAME
		if [ $? -ne 0 ]; then
			INSTALL_CMD="yum install -y"
			rlRun "$INSTALL_CMD $KERNEL_DEBUGINFO_PKG_NAME" 0 "Installing ($KERNEL_DEBUGINFO_PKG_NAME) via ($INSTALL_CMD)"
		fi
		rlRun "rpmquery $KERNEL_DEBUGINFO_PKG_NAME" 0 "Correct debuginfo is installed ($KERNEL)"
		# return Skip when correct kernel debug is not installed
		if [ $? -ne 0 ]; then
			echo "Correct kernel debuginfo pkg: ${KERNEL_DEBUGINFO_PKG_NAME} is not installed" | tee -a ${OUTPUTFILE}
			rstrnt-report-result $TEST SKIP
			exit 0
		fi
		echo "==================== kernel packages installed ===================="
		rpmquery -a | grep -e kernel -e perf
		echo "==================================================================="
		rlCheckRpm $PACKAGE-debuginfo || rlRun "debuginfo-install -y $PACKAGE"
		rlAssertRpm $PACKAGE-debuginfo
		# we need iputils-debuginfo for the sake of `perf test inet_pton` testcase
		rlCheckRpm iputils-debuginfo || rlRun "debuginfo-install -y iputils"
		rlAssertRpm iputils-debuginfo

		# BPF tests require clang/llvm
		if rlIsRHEL '>7'; then
			rlRun "yum install -y clang llvm"
		fi
		rlCheckRpm "clang"
		rlCheckRpm "llvm"

		# BPF tests also require kernel-devel and elfutils-libelf-devel
		rlCheckRpm "kernel-devel" || rlRun "yum -y install kernel-devel"
		rlAssertRpm "kernel-devel"
		rlCheckRpm "elfutils-libelf-devel" || rlRun "yum -y install elfutils-libelf-devel"
		rlAssertRpm "elfutils-libelf-devel"

		# because of BPF tests, we need more memory to be lockable
		OLD_ULIMIT_L=`ulimit -l`
		# experimentally found that 4096 should be enough, may be necessary to bump in future
		NEW_ULIMIT_L=4096
		ulimit -l $NEW_ULIMIT_L
		rlAssertEquals "uname -l should be bumped to $NEW_ULIMIT_L" `ulimit -l` $NEW_ULIMIT_L

		mkdir TMP ; cd TMP
		export TmpDir=`pwd`
		cd ..

		# PREPARE ALLOWLISTS
		prepare_allowlists

		# This is important: remember the original sample rate to be restored later
		#
		# Various heavy tests may lead to that kernel throttles the sample rate too much
		# which may cause other tests to fail and such failures look mysterious and are
		# hard to investigate and reproduce. This should harden the test to be less prone
		# to this type of problems.
		ORIGINAL_SAMPLE_RATE=`sysctl kernel.perf_event_max_sample_rate | tr -d ' ' | cut -d= -f2`
		echo "ORIGINAL SAMPLE RATE = $ORIGINAL_SAMPLE_RATE" | tee -a ${OUTPUTFILE}
		REASONABLE_SAMPLE_RATE=20000
		if [ $ORIGINAL_SAMPLE_RATE -lt $REASONABLE_SAMPLE_RATE ]; then
			echo "(it seems to be too low, so increasing it to $REASONABLE_SAMPLE_RATE" | tee -a ${OUTPUTFILE}
			ORIGINAL_SAMPLE_RATE=$REASONABLE_SAMPLE_RATE
		fi

		rlRun "pushd $TmpDir >/dev/null"
		rlRun "perf test list |& perl -pe 's/ \(exclusive\)$//' | tee tests.list" 0 "We will run the following tests:"
	rlPhaseEnd

	while read line; do
		CURRENT_TEST="$line"
		# we found the end of the file
		test -n "$CURRENT_TEST" || break

		# parse the line
		TEST_NUMBER="`echo $line | perl -ne 'print $1 if /^(\d+):\s/'`"
		TEST_DESC="`echo $line | perl -pe 's/^\d+:\s//'`"
		TEST_PATTERNS="-e \"$TEST_DESC\""

		# skip in case of subtest
		test -z $TEST_NUMBER && continue

		rlPhaseStart FAIL "TEST #$TEST_NUMBER : $TEST_DESC"
			if check_allowlisted "$TEST_DESC"; then
				rlLog "[ ALLOWLISTED ] :: $TEST_NUMBER: $TEST_DESC  (known issue)"
			else
				perf test -F -vv $TEST_NUMBER &> $TEST_NUMBER.log
				RETVAL=$?
				rlLog "$(cat $TEST_NUMBER.log)"
				# use eval to correctly interpret the patters, -F to not match regex characters
				RESULT=`eval grep -F "$TEST_PATTERNS" < $TEST_NUMBER.log | grep : | awk -F':' '{print $NF}' | tr -d ' ' | grep -oP "^[\s\w]+" | tr -d '\n'`
				printf "%8s -- %s\n" $RESULT "$CURRENT_TEST" | tee -a results.log

				# search for successful report, not fail for testcase with subtests
				echo $RESULT | grep -iE "Ok|Skip" | grep -qiv "FAIL"
				if [ $? -eq 0 ] && [ $RETVAL -eq 0 ]; then
					rlPass "$TEST_NUMBER: $TEST_DESC"
				else
					rlFail "$TEST_NUMBER: $TEST_DESC"
					rlFileSubmit "$TEST_NUMBER.log"
				fi

				# restore original sample rate to ensure the tests dependent on it pass
				# more info: bz1532741#c18
				sysctl kernel.perf_event_max_sample_rate=$ORIGINAL_SAMPLE_RATE
			fi
		rlPhaseEnd
	done < tests.list

	# bz1414043 coverage
	rlPhaseStartTest "bz1414043 coverage -- \"Session topology\" test fails with some CPUs disabled"
		# check if we have enough CPUs (at least two)
		if [ `nproc` -lt 2 ]; then
			rlLog "bz1414043 coverage skipped (we need at least 2 cpus)"
		else
			# check if the test is not disabled on this machine
			TEST_NUMBER="`perf test list |& grep topology | perl -ne 'print $1 if /^(\d+):\s/'`"
			TEST_DESC="`perf test list |& grep topology | perl -pe 's/^\s*\d+:\s//'`"
			if check_allowlisted "$TEST_DESC" || check_allowlisted "Session topology with CPU disabled"; then
				rlLog "bz1414043 coverage skipped (allowlisted)"
			else
				# check if we can disable a cpu (we sometimes cannot on aarch64)
				if echo 0 > /sys/devices/system/cpu/cpu1/online; then
					# now it should be OK, so test!
					rlRun "perf test -v topology" 0 "bz1414043 test (should PASS)" # BUG REPRODUCTION ASSERT
					rlRun "echo 1 > /sys/devices/system/cpu/cpu1/online" 0 "Turning the cpu1 back on"
				else
					rlLog "bz1414043 coverage skipped (cannot turn cpu1 off)"
				fi
			fi
		fi
	rlPhaseEnd

	# this test is suitable for kernels version 3 and newer
	KERNEL_MAJOR_VERSION=`uname -r | perl -ne 'print "$1" if /^(\d+)\./'`
	if [ $KERNEL_MAJOR_VERSION -ge 3 ]; then
	# bz1308907 coverage
	rlPhaseStartTest "bz1308907 coverage -- FAILED '/usr/libexec/perf-core/tests/attr/test-stat-C0' - match failure"
		# check if the test is not disabled on this machine
		TEST_NUMBER="`perf test list |& grep perf_event_attr | perl -ne 'print $1 if /^\s*(\d+):\s/'`"
		TEST_DESC="`perf test list |& grep perf_event_attr | perl -pe 's/^\s*\d+:\s//'`"
		if check_allowlisted "$TEST_DESC"; then
			rlLog "bz1308907 coverage skipped (allowlisted)"
		elif [ -z "$TEST_NUMBER" ]; then
			rlLog "bz1308907 coverage skipped (could not parse the test number)"
		else
			# in case max sample rate was lowered by previous tests
			rlRun "echo $REASONABLE_SAMPLE_RATE > /proc/sys/kernel/perf_event_max_sample_rate" 0 "Updating sample rate to $REASONABLE_SAMPLE_RATE"
			# the corresponding perf-test should NOT contain the following line in the output:
			# FAILED '/usr/libexec/perf-core/tests/attr/test-stat-C0' - match failure
			rlRun "perf test -v $TEST_NUMBER |& grep FAILED" 1 "bz1308907 test (should PASS)" # BUG REPRODUCTION ASSERT
		fi
	rlPhaseEnd
	fi

	rlPhaseStartCleanup
		rlRun "tar c * | xz > logs-`date +%s`.tar.xz"
		rlFileSubmit "logs-*.tar.xz"
		echo "===========================[ results ]============================="
		cat results.log
		echo "==================================================================="
		rlRun "popd >/dev/null"
		rlRun "rm -rf $TmpDir"
		# restore the sample rate back to the original or something reasonable
		sysctl kernel.perf_event_max_sample_rate=$ORIGINAL_SAMPLE_RATE
		# restore ulimit -l back
		ulimit -l $OLD_ULIMIT_L
		rlAssertEquals "uname -l should be restored back to $OLD_ULIMIT_L" `ulimit -l` $OLD_ULIMIT_L

	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
