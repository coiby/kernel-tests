#!/bin/bash

TNAME="storage/blktests/nvme/nvmeof-mp"

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 1

function pre_setup
{
	echo "options nvme_core multipath=N"  > /etc/modprobe.d/nvme.conf
	if [ -e "/sys/module/nvme_core/parameters/multipath" ]; then
		modprobe -qfr nvme_rdma nvme_fabrics nvme nvme_core
		modprobe nvme
	fi
}


function get_test_cases
{
	typeset testcases=""

	[[ $(ip -4 -o a s | grep -cv "127.0.0.1") != 1 ]] || testcases+=" nvmeof-mp/001"
	#RHEL8 aarch64 BZ1919363 BZ1938434, RHEL9 #BZ191296, RHEL-8.2 BZ2058980
	uname -ri | grep -qE "4.18.0-193|4.18.0.*aarch64|4.18.0.*ppc64le|5.12.*aarch64|el9.ppc64le|5.11.*ppc64le" || testcases+=" nvmeof-mp/002"
	# testcases+=" nvmeof-mp/004", need legacy device mapper support
	testcases+=" nvmeof-mp/005"
	testcases+=" nvmeof-mp/006"
	testcases+=" nvmeof-mp/009"
	testcases+=" nvmeof-mp/010"
	testcases+=" nvmeof-mp/011"
	testcases+=" nvmeof-mp/012"

	echo "$testcases"
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
	testcases_default=""
	testcases_default+=" $(get_test_cases)"
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
	. "$CDIR"/../include/build.sh

	main
fi

