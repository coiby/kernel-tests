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

function get_test_cases_srp
{
	typeset testcases=""
	testcases+=" srp/001"
	# srp/002 srp/011 srp/015 failure on ppc64le|x86_64|aarch64, BZ1938508|BZ1963685|BZ1963696|BZ1999540
	# srp/002 failure on aarch64 BZ2000815
	# srp/002 srp/005 srp/008 failed on linux-block 5.14 s390x, unstalble rdma_rxe on upstream
	# srp/002 hang when use siw on upstream aarch64|ppc64le
	uname -ri | grep -qE "^5.*aarch64|^5.*ppc64le|4.18.0.*aarch64|4.18.0.*x86_64|4.18.0.*ppc64le|5.14.0.*x86_64|5.14.0.*ppc64le" || testcases+=" srp/002"
	# testcases+=" srp/003", need legacy device mapper support
	# testcases+=" srp/004", need legacy device mapper support
	[[ $USE_SIW =~ 0 ]] && uname -ri | grep -qE "^5.*s390x" || testcases+=" srp/005"
	testcases+=" srp/006"
	testcases+=" srp/007"
	[[ $USE_SIW =~ 0 ]] && uname -ri | grep -qE "^5.*s390x" || testcases+=" srp/008"
	testcases+=" srp/009"
	testcases+=" srp/010"
	uname -ri | grep  -qE "ppc64le|4.18.0.*aarch64|el8.x86_64|el8.ppc64le|el9.x86_64|el9.ppc64le" || testcases+=" srp/011"
	# testcases+=" srp/012", need legacy device mapper support
	# disable srp/013 for rhel8, BZ1951961
	uname -r | grep -q "4.18.0" || testcases+=" srp/013"
	uname -r | grep -q 4.18.0 || testcases+=" srp/014" #BZ1900153
	uname -ri | grep -qE "ppc64le|4.18.0.*.aarch64|el8.x86_64|el8.ppc64le|el9.x86_64|el9.ppc64le" || testcases+=" srp/015"
	echo "$testcases"
}

if [[ "$USE_SIW" =~ 0 ]] && grep -q "ipv6.disable=1" /proc/cmdline && grep -qE "8.[0-3]" /etc/redhat-release ; then
	rlLog "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

function main
{
	USE_SIW=${USE_SIW:-"0 1"}
	test_ws=./blktests
	ret=0
	testcases_default=""
	testcases_default+=" $(get_test_cases_srp)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	pre_setup
	disable_multipath
	for use_siw in $USE_SIW; do
		if (( use_siw == 0 )); then
			USE_SIW=""
		elif (( use_siw == 1 )); then
			USE_SIW="use_siw=1"
		fi
		for testcase in $testcases; do
			eval $USE_SIW do_test "$test_ws" "$testcase"
			result=$(get_test_result "$test_ws" "$testcase")
			report_test_result "$result" "$USE_SIW srp: $TNAME/tests/$testcase"
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
	. "$CDIR"/build.sh

	main
fi
