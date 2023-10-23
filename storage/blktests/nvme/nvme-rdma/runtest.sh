#!/bin/bash

TNAME="storage/blktests/nvme/nvme-rdma"
TRTYPE=${TRTYPE:-"rdma"}

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 1

function get_test_cases_rdma
{
	typeset testcases=""

	if rlIsRHEL 7; then
		testcases+=" nvme/003" # BZ1872714
		testcases+=" nvme/004" # BZ1872714
		testcases+=" nvme/006" # BZ1872714
		testcases+=" nvme/008"
		testcases+=" nvme/010"
		testcases+=" nvme/012"
		testcases+=" nvme/014"
		testcases+=" nvme/019"
		testcases+=" nvme/023"
		testcases+=" nvme/031"
	elif rlIsRHEL 8; then
		testcases+=" nvme/003"
		testcases+=" nvme/004"
		testcases+=" nvme/005"
		testcases+=" nvme/006"
		testcases+=" nvme/007"
		testcases+=" nvme/008"
		testcases+=" nvme/009"
		testcases+=" nvme/010"
		testcases+=" nvme/011"
		uname -ri | grep -qE "4.18.0.*aarch64|4.18.0.*ppc64le|el9.ppc64le" || testcases+=" nvme/012" # BZ1871774 BZ1912968
		uname -ri | grep -qE "4.18.0-147|4.18.0.*aarch64|4.18.0.*ppc64le" || testcases+=" nvme/013" # BZ1871774/dislable 013 on 8.1.z
		uname -ri | grep -qE "4.18.0.*x86_64|4.18.0.*aarch64" || testcases+=" nvme/014" #BZ1964313 disable nvme/014 on x86_64/aarch64, nvme/015 on aarch64
		uname -ri | grep -qE "4.18.0-147|4.18.0.*aarch64" || testcases+=" nvme/015" # disable 015 on 8.1.z
		testcases+=" nvme/018"
		testcases+=" nvme/019"
		testcases+=" nvme/020"
		testcases+=" nvme/021"
		testcases+=" nvme/022"
		testcases+=" nvme/023"
		testcases+=" nvme/024"
		testcases+=" nvme/025"
		testcases+=" nvme/026"
		testcases+=" nvme/027"
		testcases+=" nvme/028"
		testcases+=" nvme/029"
		uname -ri | grep -q "4.18.0-147.*s390x" || testcases+=" nvme/030" # BZ1753057, skip on 8.1.z fixed on 8.2
		uname -ri | grep -qE "el8_1|el8_6|el8_7" || testcases+=" nvme/031"
	elif rlIsRHEL 9 || rlIsFedora || rlIsCentOS 9; then
		testcases+=" nvme/003"
		testcases+=" nvme/004"
		testcases+=" nvme/005"
		testcases+=" nvme/006"
		testcases+=" nvme/007"
		testcases+=" nvme/008"
		testcases+=" nvme/009"
		testcases+=" nvme/010"
		testcases+=" nvme/011"
		testcases+=" nvme/012"
		testcases+=" nvme/013"
		testcases+=" nvme/014"
		testcases+=" nvme/015"
		testcases+=" nvme/018"
		testcases+=" nvme/019"
		testcases+=" nvme/020"
		testcases+=" nvme/021"
		testcases+=" nvme/022"
		testcases+=" nvme/023"
		testcases+=" nvme/024"
		testcases+=" nvme/025"
		testcases+=" nvme/026"
		testcases+=" nvme/027"
		testcases+=" nvme/028"
		testcases+=" nvme/029"
		testcases+=" nvme/030"
		testcases+=" nvme/031"
		testcases+=" nvme/038"
		testcases+=" nvme/040"
		testcases+=" nvme/041"
		testcases+=" nvme/042"
		testcases+=" nvme/043"
		testcases+=" nvme/044"
		testcases+=" nvme/045"
		testcases+=" nvme/047"
		uname -ri | grep -Eq "el9_0|el9_1|el9_2" || testcases+=" nvme/048"

	fi

	echo "$testcases"
}

if [[ "$USE_SIW" =~ 0 ]] && grep -q "ipv6.disable=1" /proc/cmdline && grep -qE "8.[0-3]" /etc/redhat-release; then
	rlLog "Skip test as system doesn't have IPv6, see bz1930263"
	rstrnt-report-result "$TNAME" SKIP
	exit
fi

function main {
	enable_nvme_core_multipath

	USE_SIW=${USE_SIW:-"0 1"}
	test_ws=./blktests
	ret=0
	testcases_default=""
	testcases_default+=" $(get_test_cases_rdma)"
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	for use_siw in $USE_SIW; do
		for testcase in $testcases; do
			if (( use_siw == 0 )); then
				USE_SIW=""
			elif (( use_siw == 1)); then
				USE_SIW="use_siw=1"
			fi
			eval $USE_SIW nvme_trtype=rdma do_test "$test_ws" "$testcase"
			result=$(get_test_result "$test_ws" "$testcase")
			report_test_result "$result" "$USE_SIW nvme-rdma: $TNAME/tests/$testcase"
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
