#!/bin/bash

TNAME="storage/blktests"

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 1
CASE_TYPE=BLK

function main
{
	testcases_default="$(get_test_cases_list $CASE_TYPE)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	test_ws="${CDIR}"/blktests
	ret=0
	for testcase in $testcases; do
		do_test "$test_ws" "$testcase"
		result=$(get_test_result "$test_ws" "$testcase")
		report_test_result "$result" "$TNAME/tests/$testcase"
		((ret += $?))
	done

	if [[ $ret -ne 0 ]]; then
		echo ">> There are failing tests, pls check it"
	fi
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	if cki_has_kernel_debug_flags; then
		# the test is not supported on debug kernels due to performance issues
		# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/657
		rstrnt-report-result "$TNAME" SKIP
		exit 0
	fi

	. "$CDIR"/../include/build.sh
	main
fi
