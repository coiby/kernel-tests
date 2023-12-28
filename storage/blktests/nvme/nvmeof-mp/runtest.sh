#!/bin/bash

TNAME="storage/blktests/nvme/nvmeof-mp"

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 1
CASE_TYPE=NVMEOF_MP

function pre_setup
{
	echo "options nvme_core multipath=N"  > /etc/modprobe.d/nvme.conf
	if [ -e "/sys/module/nvme_core/parameters/multipath" ]; then
		modprobe -qfr nvme_rdma nvme_fabrics nvme nvme_core
		modprobe nvme
	fi
}

if [[ "$USE_SW_RDMA" =~ RXE ]] && grep -q "ipv6.disable=1" /proc/cmdline && grep -qE "8.[0-3]" /etc/redhat-release; then
	rlLog "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

function main
{
	pre_setup

	USE_SW_RDMA=${USE_SW_RDMA:-"RXE SIW"}
	test_ws="${CDIR}"/blktests
	ret=0
	testcases_default="$(get_test_cases_list $CASE_TYPE)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	for use_sw_rdma in $USE_SW_RDMA; do
		for testcase in $testcases; do
			disable_multipath
			if [[ "$use_sw_rdma" = "RXE" ]]; then
				USE_RDMA="use_rxe=1"
			elif [[ "$use_sw_rdma" = "SIW" ]]; then
				USE_RDMA=""
			fi
			eval "$USE_RDMA" do_test "$test_ws" "$testcase"
			result=$(get_test_result "$test_ws" "$testcase")
			report_test_result "$result" "$USE_RDMA nvmeof-mp: $TNAME/tests/$testcase"
			((ret += $?))
		done
	done

	if (( ret != 0 )); then
		echo ">> There are failing tests, pls check it"
	fi

	return
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	. "$CDIR"/../../include/build.sh

	main
fi

