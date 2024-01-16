#!/bin/bash

TNAME="storage/blktests/nvme/nvme-rdma"
TRTYPE=${TRTYPE:-"rdma"}

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 1
CASE_TYPE=NVME_RDMA

if [[ "$USE_SW_RDMA" =~ RXE ]] && grep -q "ipv6.disable=1" /proc/cmdline && grep -qE "8.[0-3]" /etc/redhat-release; then
	echo "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

function main {

	enable_nvme_core_multipath

	ret=0
	test_ws="${CDIR}"/blktests
	USE_SW_RDMA=${USE_SW_RDMA:-"RXE SIW"}
	for use_sw_rdma in $USE_SW_RDMA; do
		if [[ "$use_sw_rdma" = "RXE" ]]; then
			USE_RDMA="use_rxe=1"
			case_type="${CASE_TYPE}_RXE"
		elif [[ "$use_sw_rdma" = "SIW" ]]; then
			USE_RDMA=""
			case_type="${CASE_TYPE}_SIW"
		fi
		testcases_default="$(get_test_cases_list $case_type)"
		testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
		if [ -z "$testcases" ]; then
			echo "Skip test because $case_type list is empty"
			rstrnt-report-result "$TNAME" SKIP
		fi
		for testcase in $testcases; do
			eval $USE_RDMA nvme_trtype=rdma do_test "$test_ws" "$testcase"
			result=$(get_test_result "$test_ws" "$testcase")
			report_test_result "$result" "$USE_RDMA nvme-rdma: $TNAME/tests/$testcase"
			((ret += $?))
		done
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
