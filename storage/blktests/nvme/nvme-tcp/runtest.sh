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

TNAME="storage/blktests/nvme/nvme-tcp"
TRTYPE=${TRTYPE:-"tcp"}

source ../../include/include.sh || exit 1

function enable_nvme_core_multipath
{
	modprobe nvme_core
	if [ -e "/sys/module/nvme_core/parameters/multipath" ]; then
		modprobe -qfr nvme_rdma nvme_fabrics nvme nvme_core
		echo "options nvme_core multipath=Y"  > /etc/modprobe.d/nvme.conf
		modprobe nvme
		#wait enough time for NVMe disk initialized
		sleep 5
	fi
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
	elif [[ $result == "SKIP" || $result == "UNTESTED" ]]; then
		rstrnt-report-result "nvme-$trtype: $TNAME/tests/$test_case" SKIP 0
		ret=0
	else
		rstrnt-report-result "nvme-$trtype: $TNAME/tests/$test_case" WARN 2
		ret=2
	fi

	return $ret
}

function get_test_cases_tcp
{
	typeset testcases=""
	if ! rlIsRHEL 7; then
		testcases+=" nvme/003"
		testcases+=" nvme/004"
		testcases+=" nvme/005"
		testcases+=" nvme/006"
		testcases+=" nvme/007"
		testcases+=" nvme/008"
		testcases+=" nvme/009"
		testcases+=" nvme/010"
		testcases+=" nvme/011"
		# BZ1875640, disable on 8.2.z and 8.3
		uname -ri | grep -q "4.18.0-193.*x86_64" || grep -q 8.3 /etc/redhat-release || testcases+=" nvme/012"
		uname -ri | grep -q "4.18.0-147" || testcases+=" nvme/013"
		testcases+=" nvme/014"
		uname -ri | grep -q "4.18.0-147" || testcases+=" nvme/015"
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
		uname -ri | grep "4.18.0-147" | grep -qE "x86_64|s390x|ppc64le" || testcases+=" nvme/031"

	fi
	echo $testcases
}

. ../include/build.sh

enable_nvme_core_multipath

test_ws=./blktests
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
