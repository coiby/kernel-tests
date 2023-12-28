#!/bin/bash

TNAME="storage/blktests/srp"


FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 1

function pre_setup
{
	modprobe -r ib_isert ib_srpt iscsi_target_mod target_core_mod
	echo "options nvme_core multipath=N" > /etc/modprobe.d/nvme.conf
	# some servers have large CPUS, which lead srp tests hang, this also
	# exists on upstream: BZ2036032 BZ2036033
	echo "options ib_srp ch_count=10" > /etc/modprobe.d/ib_srp.conf
}

if [[ "$USE_SW_RDMA" =~ RXE ]] && grep -q "ipv6.disable=1" /proc/cmdline && grep -qE "8.[0-3]" /etc/redhat-release ; then
	rlLog "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

function main
{
	USE_SW_RDMA=${USE_SW_RDMA:-"RXE SIW"}
	test_ws="${CDIR}"/blktests
	ret=0
	testcases_default=""
	testcases_default+=" $(get_test_cases_srp)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	pre_setup
	disable_multipath
	for use_sw_rdma in $USE_SW_RDMA; do
		if [[ "$use_sw_rdma" == "RXE" ]]; then
			USE_RDMA="use_rxe=1"
			case_type="${CASE_TYPE}_RXE"
		elif [[ "$use_sw_rdma" == "SIW" ]]; then
			USE_RDMA=""
			case_type="${CASE_TYPE}_SIW"
		fi
		testcases_default="$(get_test_cases_list $case_type)"
		testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
		for testcase in $testcases; do
			eval $USE_RDMA do_test "$test_ws" "$testcase"
			result=$(get_test_result "$test_ws" "$testcase")
			report_test_result "$result" "$USE_RDMA srp: $TNAME/tests/$testcase"
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
	. "$CDIR"/../include/build.sh
	main
fi
