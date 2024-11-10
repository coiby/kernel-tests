#!/bin/bash

TNAME="storage/blktests/throtl"

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 1
CASE_TYPE=THROTL

function main
{
	ret=0
	test_ws="${CDIR}"/blktests
	testcases_default="$(get_test_cases_list $CASE_TYPE)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	if [ -z "$testcases" ]; then
		echo "Skip test because $CASE_TYPE case list is empty"
		rstrnt-report-result "$TNAME" SKIP
		return 0
	fi
	if rlIsRHEL ">9.4"|| rlIsRHEL 10 || rlIsCentOS 10 || rlIsFedora; then
		for testcase in $testcases; do
			do_test "$test_ws" "$testcase"
			result=$(get_test_result "$test_ws" "$testcase")
			report_test_result "$result" "$TNAME/tests/$testcase"
			((ret += $?))
		done
	else
		echo "Skip test because $(cat /etc/redhat-release) doesn't support throtl"
		rstrnt-report-result "$TNAME" SKIP
		return 0
	fi

	if [[ $ret -ne 0 ]]; then
		echo ">> There are failing tests, pls check it"
	fi
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	. "$CDIR"/../include/build.sh
	main
fi
