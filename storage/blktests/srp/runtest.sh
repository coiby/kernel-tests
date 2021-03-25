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
TNAME="storage/blktests/srp"
USE_SIW=${USE_SIW:-"0 1"}

source $CDIR/../../../cki_lib/libcki.sh

function pre_setup
{
	modprobe -r ib_isert ib_srpt iscsi_target_mod target_core_mod
	echo "options nvme_core multipath=N"  > /etc/modprobe.d/nvme.conf
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
	typeset result_file=$(find $result_dir -type f | egrep "$test_case$"
	typeset out_bad_file="${result_file}.out.bad")
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

	echo ">>> $(get_timestamp) | Start to run test case $USE_SIW srp: $this_case ..."
	(cd $test_ws && eval $USE_SIW ./check $test_case)
	typeset result=$(get_test_result $test_ws $test_case)
	echo ">>> $(get_timestamp) | End srp: $this_case | $result"

	typeset -i ret=0
	if [[ $result == "PASS" ]]; then
		rstrnt-report-result "$USE_SIW srp: $TNAME/tests/$test_case" PASS 0
		ret=0
	elif [[ $result == "FAIL" ]]; then
		rstrnt-report-result "$USE_SIW srp: $TNAME/tests/$test_case" FAIL 1
		ret=1
	elif [[ $result == "SKIP" ]]; then
		rstrnt-report-result "$USE_SIW srp: $TNAME/tests/$test_case" SKIP 0
		ret=0
	else
		rstrnt-report-result "$USE_SIW srp: $TNAME/tests/$test_case" WARN 2
		ret=2
	fi

	return $ret
}

function get_test_cases_srp
{
	typeset testcases=""
	testcases+=" srp/001"
	# srp/002 srp/011 srp/015 failure on ppc64le, BZ1938508
	uname -ri | grep -q "4.18.0.*ppc64le" || testcases+=" srp/002"
	# testcases+=" srp/003", need legacy device mapper support
	# testcases+=" srp/004", need legacy device mapper support
	# upstream stable branch 5.11 with 005-010 lead panic
	uname -ri | grep -q "5.11" || testcases+=" srp/005"
	uname -ri | grep -q "5.11" || testcases+=" srp/006"
	uname -ri | grep -q "5.11" || testcases+=" srp/007"
	uname -ri | grep -q "5.11" || testcases+=" srp/008"
	uname -ri | grep -q "5.11" || testcases+=" srp/009"
	uname -ri | grep -q "5.11" || testcases+=" srp/010"
	uname -ri | grep -q "4.18.0.*ppc64le" || testcases+=" srp/011"
	# testcases+=" srp/012", need legacy device mapper support
	testcases+=" srp/013"
	uname -r | grep -q 4.18.0 || testcases+=" srp/014" #BZ1900153
	uname -ri | grep -q "4.18.0.*ppc64le" || testcases+=" srp/015"
	echo $testcases
}

if [[ "$USE_SIW" =~ 0 ]] && grep -q "ipv6.disable=1" /proc/cmdline ; then
	rlLog "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

bash $CDIR/build.sh
if (( $? != 0 )); then
	rlLog "Abort test because build env setup failed"
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
fi

test_ws=$CDIR/blktests
ret=0
testcases_default=""
testcases_default+=" $(get_test_cases_srp)"
testcases=${_DEBUG_MODE_TESTCASES:-"$(echo $testcases_default)"}
for testcase in $testcases; do
	for use_siw in $USE_SIW; do
		pre_setup
		disable_multipath
		do_test $test_ws $testcase $use_siw
		((ret += $?))
	done
done

if (( $ret != 0 )); then
	echo ">> There are failing tests, pls check it"
fi

exit 0
