#!/bin/bash

TNAME="storage/blktests/nvme/nvme-fc"
TRTYPE=${TRTYPE:-"fc"}

. ../../include/include.sh || exit 1

function do_test
{
	typeset test_ws=$1
	typeset test_case=$2
	typeset trtype=$3

	typeset this_case=$test_ws/tests/$test_case
	echo ">>> $(get_timestamp) | Start to run test case nvme-$trtype: $this_case ..."
	(cd "$test_ws" && nvme_trtype="$trtype" ./check "$test_case")
	typeset result="$(get_test_result "$test_ws" "$test_case")"
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

function get_test_cases_fc
{
	typeset testcases=""

	if rlIsRHEL 9 || rlIsFedora || rlIsCentOS 9; then
		testcases+=" nvme/003"
		testcases+=" nvme/004"
		testcases+=" nvme/005"
		testcases+=" nvme/006"
		testcases+=" nvme/007"
		testcases+=" nvme/008"
		testcases+=" nvme/009"
		testcases+=" nvme/010"
		testcases+=" nvme/011"
		testcases+=" nvme/012"
		testcases+=" nvme/013"
		testcases+=" nvme/014"
		testcases+=" nvme/015"
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
		testcases+=" nvme/031"
		testcases+=" nvme/038"
		testcases+=" nvme/040"
		testcases+=" nvme/041"
		testcases+=" nvme/042"
		testcases+=" nvme/043"
		testcases+=" nvme/044"
		testcases+=" nvme/045"
		testcases+=" nvme/048"
	fi

	echo "$testcases"
}

. ../include/build.sh

enable_nvme_core_multipath

test_ws=./blktests
ret=0
trtype=$TRTYPE
testcases_default=""
testcases_default+=" $(get_test_cases_"$trtype")"
testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
for testcase in $testcases; do
	do_test "$test_ws" "$testcase" "$trtype"
	((ret += $?))
done

if (( ret != 0 )); then
	echo ">> There are failing tests, pls check it"
fi

exit 0
