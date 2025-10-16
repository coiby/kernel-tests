#!/bin/bash

# shellcheck disable=SC2034,SC2124
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /tools/perf/Sanity/perftool-testsuite-cki
#   Description: the test runs upstream perftool-testsuite in CKI
#   Author: Michael Petlan <mpetlan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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
. denylist.sh

PACKAGE="perf"

# configuration
GIT_CLONE_ATTEMPTS_COUNT=25
KEEP_LOGS="no"
PERFTESTS_ENABLE_DENYLIST=${PERFTESTS_ENABLE_DENYLIST:-1}

# constants
RUNMODE_BASIC=0
RUNMODE_STANDARD=1
RUNMODE_EXPERIMENTAL=2

export TESTLOG_VERBOSITY=2
export TEST_IGNORE_MISSING_PMU=y
export PERFTOOL_TESTSUITE_RUNMODE=$RUNMODE_BASIC

# hook, someone likes using "True" there, we like 1, 0 values more
if [ "$PERFTESTS_ENABLE_DENYLIST" = "true" ] || [ "$PERFTESTS_ENABLE_DENYLIST" = "True" ]; then
	PERFTESTS_ENABLE_DENYLIST=1
fi

# select tool to manage package, which could be "yum" or "dnf"
select_yum_tool()
{
	if [ -x /usr/bin/dnf ]; then
		echo "/usr/bin/dnf"
	elif [ -x /usr/bin/yum ]; then
		echo "/usr/bin/yum"
	else
		return 1
	fi

	return 0
}

skip_testcase()
{
	echo "$1" | tee -a ${OUTPUTFILE}
	rlReport $TEST SKIP
	rlPhaseEnd
	rlJournalPrintText
	rlJournalEnd
	exit 0
}


fetch_the_testsuite()
{
	test -e perftool-testsuite && return

	REPO_CLONED=0
	for (( i=0; i<$GIT_CLONE_ATTEMPTS_COUNT; i++ )); do
		echo "Trying to clone the repo....... take $i..."
		git clone https://github.com/rfmvh/perftool-testsuite.git
		if [ $? -eq 0 ]; then
			echo "Oh dear, I have been able to clone the repo. Yeah!!!"
			REPO_CLONED=1
			break
		fi
	done
	if [ $REPO_CLONED -ne 1 ]; then
		rlLog "I have not been able to clone the repo in $GIT_CLONE_ATTEMPTS_COUNT takes....."
	else
		rlPass "The REPO has been cloned!"
	fi
}

# K_Vercmp() returns one of the following values in the global K_KVERCMP_RET:
#   -1 if kernel version from argument $1 is older
#    0 if kernel version from argument $1 is the same as $2
#    1 if kernel version from argument $1 is newer
K_KVERCMP_RET=0
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

waive_fails()
{
	local architecture="$1"; shift
	local kernel_version="$1"; shift
	local test_name="$@"

	for fail in "${DENYLIST[@]}"
	do
		set -- $fail
		local denylist_result=$1; shift
		local denylist_arch=$1; shift
		local denylist_kernel_version_start=$1; shift
		local denylist_kernel_version_end=$1; shift
		local denylist_name="$@"

		grep -q "$architecture," <<<"$denylist_arch" || continue
		grep -q "$denylist_name" <<<"$test_name" || continue
		K_Vercmp $kernel_version $denylist_kernel_version_start
		[[ $K_KVERCMP_RET -ge "0" ]] || continue
		K_Vercmp $kernel_version $denylist_kernel_version_end
		[[ $K_KVERCMP_RET -lt "0" ]] || continue
		return 0
	done
	return 1
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

		# do some environment logging
		ARCH=`arch`
		KERNEL=`uname -r`
		YUM=`select_yum_tool`
		rlLog "RUNNING KERNEL: $KERNEL"
		lscpu | while read line; do rlLog "$line"; done; unset line # log the CPU
		rlLog "AUXV: `LD_SHOW_AUXV=1 /bin/true | grep PLATFORM`"
		if [[ $ARCH =~ ppc64.* ]]; then
			# detect POWER virtualization
			rlLog "Virtualization: `systemd-detect-virt -q && echo PowerKVM || ( test -e /proc/ppc64/lparcfg && echo PowerVM || echo none )`"
		else
			# detect virtualization
			rlLog "Virtualization: `virt-what`"
		fi
		unset ARCH

		kernel_name=$(rpm -q --queryformat '%{name}\n' -qf "/boot/config-$(uname -r)" | sed 's/-core//')
		KERNEL_PKG_NAME="$kernel_name-$KERNEL"
		KERNEL_DEBUGINFO_PKG_NAME="$kernel_name-debuginfo-$KERNEL"

		# strip-off the "+debug" or "+64k" suffix if present
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
			# we need to install debuginfo for the proper kernel
			# but sometimes, debuginfo-install is not available!
			which debuginfo-install || rlRun "$YUM -y install yum-utils dnf-utils" 0 "Installing {yum,dnf}-utils (it has not been present)"
			which debuginfo-install # now it should be installed, but what if it fails...
			if [ $? -eq 0 ]; then
				rlRun "debuginfo-install -y $KERNEL_DEBUGINFO_PKG_NAME" 0 "Installing debuginfo for $KERNEL_PKG_NAME via debuginfo-install"
			else
				# as debuginfo repos can be disabled by default, when using yum/dnf make sure to try with all repos enabled
				rlRun "$YUM install -y --enablerepo=* $KERNEL_DEBUGINFO_PKG_NAME" 0 "Installing debuginfo for $KERNEL_PKG_NAME via yum/dnf (unable to obtain debuginfo-install)"
			fi
		fi
		rlRun "rpmquery $KERNEL_DEBUGINFO_PKG_NAME" 0 "Correct debuginfo is installed ($KERNEL)"
		# return Skip when correct kernel debug is not installed
		if [ $? -ne 0 ]; then
			skip_testcase "Correct kernel debuginfo pkg: ${KERNEL_DEBUGINFO_PKG_NAME} is not installed"
		fi
		echo "==================== kernel packages installed ===================="
		rpmquery -a | grep -e kernel -e perf
		echo "==================================================================="

		# log whether we use denylisting
		if [ $PERFTESTS_ENABLE_DENYLIST -ne 0 ]; then
			rlLog "DENYLISTING ENABLED (known fails will be hidden)"
		else
			rlLog "DENYLISTING DISABLED"
		fi

		# set kptr_restrict to 0
		PREVIOUS_KPTR_RESTRICT=`cat /proc/sys/kernel/kptr_restrict`
		rlRun "echo 0 > /proc/sys/kernel/kptr_restrict"
		rlAssert0 "kptr_restrict must be set to 0" `cat /proc/sys/kernel/kptr_restrict`

		# clone the upstream perftool-testsuite repo
		fetch_the_testsuite
		# return SKip if the testsuite could not be fetched
		test -d "perftool-testsuite" || cki_abort_task "Could not fetch the upstream testsuite from github. I am sorry, dude."

		pushd perftool-testsuite
	rlPhaseEnd

	for group in base_*; do
		cd $group
		rlPhaseStartTest "perf ${group##base_} test"
			rm -rf logs
			mkdir -p logs
			# all the tests
			for testcase in setup.sh test_*; do
				# skip setup.sh if not present or not executable
				test -x $testcase || continue
				if [ $PERFTESTS_ENABLE_DENYLIST -eq 0 ]; then
					# running the test without denylisting
					rlRun "./$testcase" 0 "Running test $testcase"
				else
					# denylisting enabled
					./$testcase | tee logs/${testcase}.txt

					# parse the result, accounting for known failures
					grep '^\-\-' logs/${testcase}.txt | while read -r line
					do
						result=$(sed -e 's,-- \[ \(.*\) \] -- .*,\1,g' <<< $line)
						testname=$(sed -e 's,-- \[ .* \] -- \(.*\),\1,g' <<< $line)
						if [ "$result" = "FAIL" ]; then
							# FAIL, try to waive it
							waive_fails $ARCH $KERNEL "$testname"
							if [ $? -ne 0 ]; then
								rlFail "[ FAIL ]  $testname"
							else
								rlPass "[WAIVED]  $testname"
							fi
						else
							# PASS or SKIP, just log and assert PASS
							rlPass "[ $result ]  $testname"
						fi
					done
				fi
			done

			# clean-up
			if [ ! "$KEEP_LOGS" = "yes" ]; then
				test -e cleanup.sh && rlRun "./cleanup.sh" 0 "Running clean-up for ${group##base_}"
			fi
		rlPhaseEnd
		cd ..
	done

	rlPhaseStartCleanup
		rlRun "echo $PREVIOUS_KPTR_RESTRICT > /proc/sys/kernel/kptr_restrict" 0 "Restoring kptr_restrict to $PREVIOUS_KPTR_RESTRICT"
		rlRun "popd"
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
