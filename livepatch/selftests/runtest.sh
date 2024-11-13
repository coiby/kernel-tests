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
. ../../general/kpatch/include/lib.sh

set -x
#-------------------- Setup --------------------
SKIP=4
BUILDS_URL="${BUILDS_URL:-}"

# Test items

TEST_ITEMS=${TEST_ITEMS:-"livepatch"}
nfail=0

skip_tests=(
)

# usage: check_skipped_tests test_name "${skip_test[@]}"
check_skipped_tests()
{
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
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

do_livepatch()
{
	[ ! -d $LIVEPATCH_TEST_MODULES ] && test_fail "$LIVEPATCH_TEST_MODULES does not exist" && return 1 || cd $LIVEPATCH_TEST_MODULES

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
install_selftests_internal || { test_fail "install selftests failed" && exit 0; }
if is_rhel "10" ; then
	build_selftests_modules || { test_fail "build selftests modules failed" && exit 0; }
fi

# the test relies on dmesg output, in some cases some other task in the background can
# clear it. Let's wait a bit for them to finish
# example: https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1967
echo "INFO: waiting 60 seconds before running the tests..."
sleep 60

for item in $TEST_ITEMS; do
	do_${item}
done

#-------------------- Clean Up --------------------
for mod in $(lsmod | grep -E "^test_klp_" | awk '{ print $1; }'); do
	rmmod -f $mod
done
