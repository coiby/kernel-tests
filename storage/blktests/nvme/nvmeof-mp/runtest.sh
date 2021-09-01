#!/bin/sh
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

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)
TNAME="storage/blktests/nvme/nvmeof-mp"
USE_SIW=${USE_SIW:-"0 1"}

source $CDIR/../../../../cki_lib/libcki.sh

function pre_setup
{
	echo "options nvme_core multipath=N"  > /etc/modprobe.d/nvme.conf
	if [ -e "/sys/module/nvme_core/parameters/multipath" ]; then
		modprobe -r nvme nvme_core
		modprobe nvme
	fi
}

function disable_multipath
{
	pidof multipathd &>/dev/null && pkill -9 multipathd
	[ -f /etc/multipath.conf ] && rm -f /etc/multipath.conf
}

function get_timestamp
{
	date +"%Y-%m-%d %H:%M:%S"
}

function get_test_result
{
	typeset test_ws=$1
	typeset test_case=$2

	typeset result_dir="$test_ws/results"
	typeset result_file=$(find $result_dir -type f | egrep "$test_case$")
	typeset out_bad_file="${result_file}.out.bad"
	typeset result="UNTESTED"
	if [[ -n $result_file ]]; then
		typeset res=$(grep "^status" $result_file)
		if [[ $res == *"pass" ]]; then
			result="PASS"
		elif [[ $res == *"fail" ]]; then
			result="FAIL"
			[ -f $out_bad_file ] && cki_upload_log_file "$out_bad_file"
		elif [[ $res == *"not run" ]]; then
			result="SKIP"
		else
			result="OTHER"
		fi
	fi

	echo $result
}

function do_test
{
	typeset test_ws=$1
	typeset test_case=$2
	typeset this_case=$test_ws/tests/$test_case
	typeset use_siw=$3
	typeset USE_SIW

	if (( $use_siw == 0 )); then
		USE_SIW=""
	elif (($use_siw == 1)); then
		USE_SIW="use_siw=1"
	fi

	echo ">>> $(get_timestamp) | Start to run test case $USE_SIW nvmeof-mp: $this_case ..."
	(cd $test_ws && eval $USE_SIW ./check $test_case)
	typeset result=$(get_test_result $test_ws $test_case)
	echo ">>> $(get_timestamp) | End nvmeof-mp: $this_case | $result"

	typeset -i ret=0
	if [[ $result == "PASS" ]]; then
		rstrnt-report-result "$USE_SIW nvmeof-mp: $TNAME/tests/$test_case" PASS 0
		ret=0
	elif [[ $result == "FAIL" ]]; then
		rstrnt-report-result "$USE_SIW nvmeof-mp: $TNAME/tests/$test_case" FAIL 1
		ret=1
	elif [[ $result == "SKIP" ]]; then
		rstrnt-report-result "$USE_SIW nvmeof-mp: $TNAME/tests/$test_case" SKIP 0
		ret=0
	else
		rstrnt-report-result "$USE_SIW nvmeof-mp: $TNAME/tests/$test_case" WARN 2
		ret=2
	fi

	return $ret
}

function get_test_cases
{
	typeset testcases=""
	[[ $(ip -4 -o a s | grep -v "127.0.0.1" | wc -l) != 1 ]] || testcases+=" nvmeof-mp/001"
	#RHEL8 aarch64 BZ1919363 BZ1938434, RHEL9 #BZ1912968
	uname -ri | grep -qE "4.18.0.*aarch64|4.18.0.*ppc64le|5.12.*aarch64|el9.ppc64le|5.11.*ppc64le" || testcases+=" nvmeof-mp/002"
	# testcases+=" nvmeof-mp/004", need legacy device mapper support
	testcases+=" nvmeof-mp/005"
	testcases+=" nvmeof-mp/006"
	testcases+=" nvmeof-mp/009"
	testcases+=" nvmeof-mp/010"
	testcases+=" nvmeof-mp/011"
	uname -ri | grep -qE "4.18.0.*x86_64|4.18.0.*ppc64le" || testcases+=" nvmeof-mp/012"  #BZ2000074
	echo $testcases
}

if [[ "$USE_SIW" =~ 0 ]] && grep -q "ipv6.disable=1" /proc/cmdline ; then
	rlLog "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

bash $CDIR/../include/build.sh
if (( $? != 0 )); then
	rlLog "Abort test because build env setup failed"
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
fi

pre_setup

test_ws=$CDIR/blktests
ret=0
testcases_default=""
testcases_default+=" $(get_test_cases)"
testcases=${_DEBUG_MODE_TESTCASES:-"$(echo $testcases_default)"}
for testcase in $testcases; do
	for use_siw in $USE_SIW; do
		disable_multipath
		do_test $test_ws $testcase $use_siw
		((ret += $?))
	done
done

if (( $ret != 0 )); then
	echo ">> There are failing tests, pls check it"
fi

exit 0
