#!/bin/bash

TNAME="storage/blktests/nvme/nvme-loop"
TRTYPE=${TRTYPE:-"loop"}

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 1
CASE_TYPE=NVME_LOOP

function main
{
	enable_nvme_core_multipath

	ret=0
	test_ws="${CDIR}"/blktests
	trtype=$TRTYPE
	testcases_default="$(get_test_cases_list $CASE_TYPE)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	if [ -z "$testcases" ]; then
		echo "Skip test because $CASE_TYPE case list is empty"
		rstrnt-report-result "$TNAME" SKIP
	fi
	if [ -n "$SKIP_STORAGE_TEST" ]; then
		testcases=$(filter_testcases "$testcases" "$SKIP_STORAGE_TEST")
	fi
	for testcase in $testcases; do
		if (rlIsRHEL ">9.4" || rlIsRHEL 10 || rlIsCentOS 10 || rlIsCentOS 9 || rlIsFedora) && [[ "$DCLIST" =~ $testcase ]]; then
			for NVMET_BLKDEV_TYPE in device file; do
				nvme_trtype="$trtype" NVMET_BLKDEV_TYPES=$NVMET_BLKDEV_TYPE do_test "$test_ws" "$testcase"
				result=$(get_test_result "$test_ws" "$testcase")
				report_test_result "$result" "NVMET_BLKDEV_TYPES=$NVMET_BLKDEV_TYPE nvme-$trtype: $TNAME/tests/$testcase"
				((ret += $?))
			done
		else
			nvme_trtype="$trtype" do_test "$test_ws" "$testcase"
			result=$(get_test_result "$test_ws" "$testcase")
			report_test_result "$result" "nvme-$trtype: $TNAME/tests/$testcase"
			((ret += $?))
		fi
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
