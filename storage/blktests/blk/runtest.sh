#!/bin/bash

TNAME="storage/blktests"

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 1
CASE_TYPE=BLK

function main
{
	ret=0
	test_ws="${CDIR}"/blktests
	testcases_default="$(get_test_cases_list $CASE_TYPE)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	if [ -z "$testcases" ]; then
		echo "Skip test because $CASE_TYPE case list is empty"
		rstrnt-report-result "$TNAME" SKIP
	fi
	if rlIsRHEL 9; then
		dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
		yum -y install nbd
	fi
	for testcase in $testcases; do
		if (rlIsRHEL ">9.4" || rlIsCentOS 9) && [[ "$testcase" == "block/035" ]]; then
			sysctl -w kernel.io_uring_disabled=0
		fi
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
	. "$CDIR"/../include/build.sh
	main
fi
