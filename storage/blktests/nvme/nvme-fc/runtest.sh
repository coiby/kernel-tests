#!/bin/bash

TNAME="storage/blktests/nvme/nvme-fc"
TRTYPE=${TRTYPE:-"fc"}

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 1

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

function main
{
	enable_nvme_core_multipath

	test_ws="${CDIR}"/blktests
	ret=0
	trtype=$TRTYPE
	testcases_default=""
	testcases_default+=" $(get_test_cases_"$trtype")"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	for testcase in $testcases; do
		nvme_trtype="$trtype" do_test "$test_ws" "$testcase"
		result=$(get_test_result "$test_ws" "$testcase")
		report_test_result "$result" "nvme-$trtype: $TNAME/tests/$testcase"
		((ret += $?))
	done

	if (( ret != 0 )); then
		echo ">> There are failing tests, pls check it"
	fi

	return
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	. "$CDIR"/../include/build.sh

	main
fi
