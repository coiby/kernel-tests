#!/bin/bash

TNAME="storage/blktests/nvme/nvme-tcp"
TRTYPE=${TRTYPE:-"tcp"}

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 1
CASE_TYPE=NVME_TCP

function main
{
	enable_nvme_core_multipath

	test_ws="${CDIR}"/blktests
	ret=0
	trtype=$TRTYPE
	testcases_default="$(get_test_cases_list $CASE_TYPE)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	if [ -z "$testcases" ]; then
		cki_abort_task "Abort test because $case_type case list is empty"
	fi
	for testcase in $testcases; do
		nvme_trtype="$trtype" do_test "$test_ws" "$testcase"
		result=$(get_test_result "$test_ws" "$testcase")
		report_test_result "$result" "nvme-$trtype: $TNAME/tests/$testcase"
		((ret += $?))
	done

	if (( ret != 0 )); then
		echo ">> There are failing tests, pls check it"
	fi
}
# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	. "$CDIR"/../../include/build.sh
	main
fi
