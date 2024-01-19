#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/livepatch/selftests
#   Description: selftests
#   Author: Joe Lawrence <joe.lawrence@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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
# Global parameters
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. kvercmp.sh

set -x
#-------------------- Setup --------------------
EXEC_DIR=/usr/libexec/kselftests/
SKIP=4
BUILDS_URL="${BUILDS_URL:-}"

# Test items

TEST_ITEMS=${TEST_ITEMS:-"livepatch"}
nfail=0

skip_tests=(
)

karch=$(uname -m)
kver=$(uname -r | cut -f1 -d'-')
krel=$(uname -r | cut -f2 -d'-' | sed -e "s/\.$karch$//" -e "s/\.$karch+debug$//" -e "s/\.$karch.debug$//")

debug_kernel()
{
	uname -r | grep -E -q "[.+]debug$"
}

# usage: check_skipped_tests test_name "${skip_test[@]}"
check_skipped_tests()
{
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

# build test modules from sources and change EXEC_DIR to kernel source tree
build_selftests()
{
	local devel
	local config
	local extraversion

	# Download (if necessary) and install kernel source rpm
	if [[ ! -e "kernel-${kver}-${krel}.src.rpm" ]]; then
		# Download and install kernel source rpm
		yumdownloader -q -y --source kernel-${kver}-${krel} \
		  || wget ${BUILDS_URL}/kernel/${kver}/${krel}/src/kernel-${kver}-${krel}.src.rpm
	fi
	rpm -ivh kernel-${kver}-${krel}.src.rpm

	# Install kernel-devel for its Modules.symvers file
	if debug_kernel; then
		devel="kernel-debug-devel"
	else
		devel="kernel-devel"
	fi
	yum install -q -y ${devel}-${kver}-${krel} \
	   || yum install -q -y ${BUILDS_URL}/kernel/${kver}/${krel}/${karch}/${devel}-${kver}-${krel}.${karch}.rpm

	# Add a backports as needed, backports/* directories hold fixes
	# for kernels greater or equal to the directory name and only
	# the latest directory applies.
	local path
	local backports
	for path in backports/*; do
		if [[ -d "$path" ]] ; then
			[[ $(kvercmp "$(uname -r)" "$(basename "$path")") -ne "-1" ]] && backports="$path"
		fi
	done
	[[ -n "$backports" ]] && cat "$backports"/*.patch > ~/rpmbuild/SOURCES/linux-kernel-test.patch

	# Install kernel build dependencies
	cd ~/rpmbuild/SPECS
	yum-builddep -y ./kernel.spec

	# Prep kernel sources
	rpmbuild -bp kernel.spec
	cd ~/rpmbuild/BUILD/kernel-${kver}-${krel}/linux-${kver}-${krel}.${karch}/

	# Copy appropriate kernel config and doctor the Makefile with
	# the RHEL release string
	if debug_kernel; then
		config="kernel-${kver}-${karch}-debug.config"
		extraversion="-${krel}.${karch}.debug"
	else
		config="kernel-${kver}-${karch}.config"
		extraversion="-${krel}.${karch}"
	fi
	rm -f .config
	cp "configs/${config}" .config
	sed -i "s/^EXTRAVERSION =.*/EXTRAVERSION = ${extraversion}/" Makefile

	# Enable Livepatch tests, turn off module signing
	./scripts/config --set-val CONFIG_TEST_LIVEPATCH m

	# Skip vmlinux build...

	# Without building kernel, we need to link to kernel-devel's
	# Modules.symvers file,
	symvers=$(rpm -ql "${devel}-${kver}-${krel}" | grep '\<Module.symvers\>$')
	ln -s "${symvers}" Module.symvers

	# Without building the kernel, we don't have module signing keys
	# and modules_install's depmod will complain that it "Can't read
	# private key".  This seems to be benign and worth the noise to
	# skip building the kernel.

	# Build and install livepatch kernel modules
	[ "${karch}" = "ppc64le" ] && build_arch="powerpc" || \
		build_arch=${karch}
	make ARCH=$build_arch modules_prepare
	[ "$build_arch" = "powerpc" ] && make ARCH=$build_arch arch/powerpc/lib/crtsavres.o
	make -j$(nproc) ARCH=$build_arch M=lib/livepatch
	make ARCH=$build_arch M=lib/livepatch modules_install
	depmod # redundant, but seemingly required

	# change EXEC_DIR to kernel source tree
	EXEC_DIR=$(pwd)/tools/testing/selftests
}

install_selftests()
{
	rpm -q kernel-selftests-internal && return 0
	if debug_kernel; then
		modules="kernel-debug-modules-internal"
	else
		modules="kernel-modules-internal"
	fi
	# These two appease the net test part of kernel-selftests-internal
	which tc || dnf install -q -y iproute-tc
	dnf install -q -y bpftool-${kver}-${krel} \
		|| dnf install -q -y ${BUILDS_URL}/kernel/${kver}/${krel}/${karch}/bpftool-${kver}-${krel}.${karch}.rpm
	# Livepatch selftests require both modules and scripts
	dnf install -q -y ${modules}-${kver}-${krel} \
		|| dnf install -q -y ${BUILDS_URL}/kernel/${kver}/${krel}/${karch}/${modules}-${kver}-${krel}.${karch}.rpm
	dnf install -q -y kernel-selftests-internal-${kver}-${krel} \
		|| dnf install -q -y ${BUILDS_URL}/kernel/${kver}/${krel}/${karch}/kernel-selftests-internal-${kver}-${krel}.${karch}.rpm
}

test_fail()
{
	SCORE=${2:-$FAIL}
	echo -e ":: [  FAIL  ] :: Test $1" | tee -a $OUTPUTFILE

	if [ $RSTRNT_JOBID ]; then
		rstrnt-report-result -o "$OUTPUTFILE" "${TEST}/$1" "FAIL" "$SCORE"
	else
		echo -e "\n:::::::::::::::::"
		echo -e ":: [  ${RED}FAIL${RES}  ] :: Test ${TEST}/$1 FAIL $SCORE"
		echo -e ":::::::::::::::::\n"
	fi
}

test_pass()
{
	echo -e "\n:: [  PASS  ] :: Test $1" | tee -a $OUTPUTFILE
	# we don't care how many test passed
	if [ $RSTRNT_JOBID ]; then
		rstrnt-report-result -o "$OUTPUTFILE" "${TEST}/$1" "PASS" 0
	else
		echo -e "\n::::::::::::::::"
		echo -e ":: [  ${GRN}PASS${RES}  ] :: Test ${TEST}/$1"
		echo -e "::::::::::::::::\n"
	fi
}

test_skip()
{
	echo -e "\n:: [  SKIP  ] :: Test $1" | tee -a $OUTPUTFILE
	if [ $RSTRNT_JOBID ]; then
		rstrnt-report-result -o "$OUTPUTFILE" "${TEST}/$1" "SKIP" 0
	else
		echo -e "\n::::::::::::::::"
		echo -e ":: [  SKIP${RES}  ] :: Test ${TEST}/$1"
		echo -e "::::::::::::::::\n"
	fi
}

check_result()
{
	local num=$1
	local total_num=$2
	local test_folder=$3
	local test_name=$4
	local test_result=$5

	if [ "$test_result" -eq 0 ]; then
		echo "${num}..${total_num} selftests: ${test_folder}: ${test_name} [PASS]"
	elif [ "$test_result" -eq $SKIP ]; then
		echo "${num}..${total_num} selftests: ${test_folder}: ${test_name} [SKIP]"
	else
		echo "${num}..${total_num} selftests: ${test_folder}: ${test_name} [FAIL]"
	fi

	return $test_result
}

submit_log()
{
	[ ! $RSTRNT_JOBID ] && return 0
	for file in "$@"; do
		rstrnt-report-log -l $file
	done
}

do_livepatch()
{
	[ ! -d $EXEC_DIR/livepatch ] && test_fail "$EXEC_DIR/livepatch does not exist" && return 1 || cd $EXEC_DIR/livepatch

	# Start livepatch test
	local livepatch_tests=(test-*.sh)
	local total_num=${#livepatch_tests[*]}

	for num in $(seq $total_num); do
		local OUTPUTFILE="/mnt/testarea/${livepatch_tests[$num - 1]%.*}_result.log"

		check_skipped_tests "${livepatch_tests[$num - 1]}" "${skip_tests[@]}" && \
			test_skip "${num}..${total_num} selftests: livepatch: ${livepatch_tests[$num - 1]} Skip" && continue

		./${livepatch_tests[$num - 1]} &> $OUTPUTFILE
		ret=$?
#		if [ $ret -ne 0 ]; then
#			echo "livepatch ${livepatch_tests[$num - 1]} failed, triggering kernel crash to help with debugging"
#			echo 1 > /proc/sys/kernel/sysrq
#			echo c > /proc/sysrq-trigger
#		fi

		echo -e "\n=== Dmesg result ===" >> $OUTPUTFILE
		dmesg >> $OUTPUTFILE

		check_result $num $total_num livepatch ${livepatch_tests[$num - 1]} $ret
		if [ "$ret" -eq 0 ]; then
			test_pass "${num}..${total_num} selftests: livepatch: ${livepatch_tests[$num - 1]} Pass"
		elif [ "$ret" -eq $SKIP ]; then
			test_skip "${num}..${total_num} selftests: livepatch: ${livepatch_tests[$num - 1]} Skip"
		else
			test_fail "${num}..${total_num} selftests: livepatch: ${livepatch_tests[$num - 1]} Fail"
			nfail=$((nfail+1))
		fi

	done

	echo "livepatch: total $total_num, failed $nfail"

}

#-------------------- Start Test --------------------
# Test if kernel nvr is in a range with selftests support
cmp_min_rhel7=$(kvercmp `uname -r` '3.10.0-1067.el7')
cmp_max_rhel7=$(kvercmp `uname -r` '3.10.0-9999.el7')
cmp_min_rhel8=$(kvercmp `uname -r` '4.18.0-147.3.el8')

if [ "$cmp_min_rhel7" -ge "0" ] && [ "$cmp_max_rhel7" -lt "0" ]; then
	build_selftests || { test_fail "build selftests failed" && exit 1; }
elif [ "$cmp_min_rhel8" -ge "0" ]; then
	install_selftests || { test_fail "install selftests failed" && exit 1; }
else
	[ $RSTRNT_JOBID ] && rstrnt-report-result "LIVEPATCH_SELFTESTS_UNSUPPORTED" "SKIP" 0
	exit 0
fi

for item in $TEST_ITEMS; do
	do_${item}
done

# if running as restraint job, the test result is already reported as subtests
# don't exit with values different of 0. Otherwise, restraint reports it as a separate subtest
[ $RSTRNT_JOBID ] || exit $nfail
#-------------------- Clean Up --------------------
