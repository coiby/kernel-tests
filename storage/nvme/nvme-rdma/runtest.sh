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
TNAME="storage/nvme/nvme-rdma"
TRTYPE=${TRTYPE:-"rdma"}

source $CDIR/../../../cki_lib/libcki.sh

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
		modprobe -r nvme nvme_core
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
	typeset result_file=$(find $result_dir -type f | egrep "$test_case")
	typeset result="UNTESTED"
	if [[ -n $result_file ]]; then
		typeset res=$(grep "^status" $result_file)
		if [[ $res == *"pass" ]]; then
			result="PASS"
		elif [[ $res == *"fail" ]]; then
			result="FAIL"
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
	typeset trtype=$3

	typeset this_case=$test_ws/tests/$test_case
	echo ">>> $(get_timestamp) | Start to run test case nvme-$trtype: $this_case ..."
	(cd $test_ws && nvme_trtype=$trtype ./check $test_case)
	typeset result=$(get_test_result $test_ws $test_case)
	echo ">>> $(get_timestamp) | End nvme-$trtype: $this_case | $result"

	typeset -i ret=0
	if [[ $result == "PASS" ]]; then
		rstrnt-report-result "nvme-$trtype: $TNAME/tests/$test_case" PASS 0
		ret=0
	elif [[ $result == "FAIL" ]]; then
		rstrnt-report-result "nvme-$trtype: $TNAME/tests/$test_case" FAIL 1
		ret=1
	elif [[ $result == "SKIP" ]]; then
		rstrnt-report-result "nvme-$trtype: $TNAME/tests/$test_case" SKIP 0
		ret=0
	else
		rstrnt-report-result "nvme-$trtype: $TNAME/tests/$test_case" WARN 2
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
		uname -ri | grep -qE "4.18.0.*aarch64|4.18.0.*ppc64le" || testcases+=" nvme/012" # BZ1871774
		uname -ri | grep -qE "4.18.0-147|4.18.0.*aarch64|4.18.0.*ppc64le" || testcases+=" nvme/013" # BZ1871774/dislable 013 on 8.1.z
		testcases+=" nvme/014"
		uname -ri | grep -q "4.18.0-147" || testcases+=" nvme/015" # disable 015 on 8.1.z
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
		testcases+=" nvme/030"
		uname -ri | grep "4.18.0-147" | grep -Eq "s390x|ppc64le|aarch64" || testcases+=" nvme/031"
	fi
	echo $testcases
}

bash $CDIR/../include/build.sh
if (( $? != 0 )); then
	rlLog "Abort test because build env setup failed"
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
fi

enable_nvme_core_multipath

test_ws=$CDIR/blktests
ret=0
for trtype in $TRTYPE; do
	testcases_default=""
	testcases_default+=" $(get_test_cases_${trtype})"
	testcases=${_DEBUG_MODE_TESTCASES:-"$(echo $testcases_default)"}
	for testcase in $testcases; do
		do_test $test_ws $testcase $trtype
		((ret += $?))
	done
done

if (( $ret != 0 )); then
	echo ">> There are failing tests, pls check it"
fi

exit 0
