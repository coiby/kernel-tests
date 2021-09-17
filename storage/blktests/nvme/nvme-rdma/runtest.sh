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
TNAME="storage/blktests/nvme/nvme-rdma"

source $CDIR/../../../../cki_lib/libcki.sh

function is_rhel7
{
	#
	# XXX: _TREE is set in kpet-db via:
	#
	#      {% if TREE == "rhel7" %}
	#          <param name="_TREE" value="rhel7"/>
	#      {% else %}
	#          <param name="_TREE" value="rhel8|upstream"/>
	#      {% endif %}
	#
	[[ ${_TREE} == "rhel7" ]] && return 0 || return 1
}

function enable_nvme_core_multipath
{
	modprobe nvme_core
	if [ -e "/sys/module/nvme_core/parameters/multipath" ]; then
		modprobe -fr nvme_rdma nvme_fabrics nvme nvme_core
		echo "options nvme_core multipath=Y"  > /etc/modprobe.d/nvme.conf
		modprobe nvme
		#wait enough time for NVMe disk initialized
		sleep 5
	fi
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
	typeset out_full_file="${result_file}.full"
	typeset result="UNTESTED"
	if [[ -n $result_file ]]; then
		typeset res=$(grep "^status" $result_file)
		if [[ $res == *"pass" ]]; then
			result="PASS"
		elif [[ $res == *"fail" ]]; then
			result="FAIL"
			[ -f $out_bad_file ] && cki_upload_log_file "$out_bad_file" >/dev/null
			[ -f $out_full_file ] && cki_upload_log_file "$out_full_file" >/dev/null
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

	echo ">>> $(get_timestamp) | Start to run test case $USE_SIW nvme-rdma: $this_case ..."
	(cd $test_ws && eval $USE_SIW nvme_trtype=rdma ./check $test_case)
	typeset result=$(get_test_result $test_ws $test_case)
	echo ">>> $(get_timestamp) | End nvme-rdma: $this_case | $result"

	typeset -i ret=0
	if [[ $result == "PASS" ]]; then
		rstrnt-report-result "$USE_SIW nvme-rdma: $TNAME/tests/$test_case" PASS 0
		ret=0
	elif [[ $result == "FAIL" ]]; then
		rstrnt-report-result "$USE_SIW nvme-rdma: $TNAME/tests/$test_case" FAIL 1
		ret=1
	elif [[ $result == "SKIP" ]]; then
		rstrnt-report-result "$USE_SIW nvme-rdma: $TNAME/tests/$test_case" SKIP 0
		ret=0
	else
		rstrnt-report-result "$USE_SIW nvme-rdma: $TNAME/tests/$test_case" WARN 2
		ret=2
	fi

	return $ret
}

function get_test_cases_rdma
{
	typeset testcases=""
	if is_rhel7; then
		testcases+=" nvme/003" # BZ1872714
		testcases+=" nvme/004" # BZ1872714
		testcases+=" nvme/006" # BZ1872714
		testcases+=" nvme/008"
		testcases+=" nvme/010"
		testcases+=" nvme/012"
		testcases+=" nvme/014"
		testcases+=" nvme/019"
		testcases+=" nvme/023"
		testcases+=" nvme/031"
	else
		testcases+=" nvme/003"
		testcases+=" nvme/004"
		testcases+=" nvme/005"
		testcases+=" nvme/006"
		testcases+=" nvme/007"
		testcases+=" nvme/008"
		testcases+=" nvme/009"
		testcases+=" nvme/010"
		testcases+=" nvme/011"
		uname -ri | grep -qE "4.18.0.*aarch64|4.18.0.*ppc64le|el9.ppc64le" || testcases+=" nvme/012" # BZ1871774 BZ1912968
		uname -ri | grep -qE "4.18.0-147|4.18.0.*aarch64|4.18.0.*ppc64le" || testcases+=" nvme/013" # BZ1871774/dislable 013 on 8.1.z
		uname -ri | grep -qE "4.18.0.*x86_64|4.18.0.*aarch64" || testcases+=" nvme/014" #BZ1964313 disable nvme/014 on x86_64/aarch64, nvme/015 on aarch64
		uname -ri | grep -qE "4.18.0-147|4.18.0.*aarch64" || testcases+=" nvme/015" # disable 015 on 8.1.z
		testcases+=" nvme/018"
		testcases+=" nvme/019"
		testcases+=" nvme/020"
		testcases+=" nvme/021"
		testcases+=" nvme/022"
		testcases+=" nvme/023"
		testcases+=" nvme/024"
		testcases+=" nvme/025"
		testcases+=" nvme/026"
		testcases+=" nvme/027"
		testcases+=" nvme/028"
		testcases+=" nvme/029"
		uname -ri | grep -q "4.18.0-147.*s390x" || testcases+=" nvme/030" # BZ1753057, skip on 8.1.z fixed on 8.2
		uname -ri | grep "4.18.0-147" | grep -Eq "s390x|ppc64le|aarch64" || testcases+=" nvme/031"
	fi
	echo $testcases
}

if [[ "$USE_SIW" =~ 0 ]] && grep -q "ipv6.disable=1" /proc/cmdline ; then
	rlLog "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

. $CDIR/../include/build.sh
if (( $? != 0 )); then
	rlLog "Abort test because build env setup failed"
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
fi

enable_nvme_core_multipath

USE_SIW=${USE_SIW:-"0 1"}
test_ws=$CDIR/blktests
ret=0
testcases_default=""
testcases_default+=" $(get_test_cases_rdma)"
testcases=${_DEBUG_MODE_TESTCASES:-"$(echo $testcases_default)"}
for testcase in $testcases; do
	for use_siw in $USE_SIW; do
		do_test $test_ws $testcase $use_siw
		((ret += $?))
	done
done

if (( $ret != 0 )); then
	echo ">> There are failing tests, pls check it"
fi

exit 0
