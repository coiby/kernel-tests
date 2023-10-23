#!/bin/bash


TNAME="storage/blktests"

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 1

function get_test_cases_block
{
	typeset testcases=""

	if rlIsRHEL 7; then
		#
		# XXX: There are 27 cases of block testing, and these cases
		#      in the following are not available to run
		#      - block/003 # XXX: Test device is required
		#      - block/004 # XXX: Test device is required
		#      - block/005 # XXX: Test device is required
		#      - block/006
		#      - block/007 # XXX: Test device is required
		#      - block/008
		#      - block/010
		#      - block/011 # XXX: Test device is required
		#      - block/012 # XXX: Test device is required
		#      - block/013 # XXX: Test device is required
		#      - block/014
		#      - block/015
		#      - block/017
		#      - block/018
		#      - block/019
		#      - block/021
		#      - block/022
		#      - block/024
		#      - block/026
		#      - block/028
		#
		# Disable block/001 for RHEL7.2/7.3/7.4/7.5
		uname -ri | grep -qE "3.10.0-327|3.10.0-514|3.10.0-693|3.10.0-862" || testcases+=" block/001"
		#testcases+=" block/002" # Test case issue: https://lore.kernel.org/linux-block/e84b29e1-209e-d598-0828-bed5e3b98093@acm.org/
		#testcases+=" block/009" # Fail randomly on x86_64, powerpc
		# block/016 failed on RHEL7.5
		uname -ri | grep -qE "3.10.0-862" || testcases+=" block/016"
		#testcases+=" block/020" # Fail randomly on arm64, powerpc
		testcases+=" block/021"
		testcases+=" block/023"
		#testcases+=" block/025" # Fail randomly on powerpc
	elif rlIsRHEL 8; then
		# Disable block/001 for upstream s390x BZ2001597
		uname -ri | grep -qE "^5\..*s390x" || testcases+=" block/001"
		#testcases+=" block/002" # Test case issue: https://lore.kernel.org/linux-block/e84b29e1-209e-d598-0828-bed5e3b98093@acm.org/
		testcases+=" block/006"
		#testcases+=" block/009" # Fail randomly on x86_64, powerpc
		testcases+=" block/016"
		#block/017 fails on s390x
		uname -m | grep -q s390x || testcases+=" block/017"
		testcases+=" block/018"
		#testcases+=" block/020" # Fail randomly on arm64, powerpc
		testcases+=" block/021"
		testcases+=" block/023"
		#testcases+=" block/025" # Fail randomly on powerpc
	elif rlIsRHEL 9 || rlIsFedora || rlIsCentOS 9; then
		testcases+=" block/001"
		testcases+=" block/002"
		testcases+=" block/006"
		testcases+=" block/007"
		testcases+=" block/009"
		testcases+=" block/010"
		testcases+=" block/016"
		testcases+=" block/017"
		testcases+=" block/018"
		testcases+=" block/020"
		testcases+=" block/021"
		testcases+=" block/022"
		testcases+=" block/023"
		testcases+=" block/024"
		testcases+=" block/025"
		testcases+=" block/027"
		testcases+=" block/028"
		testcases+=" block/029"
		testcases+=" block/031"
		testcases+=" block/032"
		uname -ri | grep -Eq "el9_0|el9_1|el9_2" || testcases+=" block/034"
	fi

	echo "$testcases"
}

function get_test_cases_loop
{
	typeset testcases=""

	if rlIsRHEL 7; then
		#
		# XXX: There are 7 cases of loop testing, and these cases
		#      in the following are not available to run
		#      - loop/002
		#      - loop/004
		#      - loop/007
		testcases+=" loop/001"
		testcases+=" loop/003"
		testcases+=" loop/005"
		testcases+=" loop/006"
	elif rlIsRHEL 8; then
		#
		# XXX: There are 7 cases of loop testing, and these cases
		#      in the following are not available to run
		#      - loop/006
		#      - loop/007
		#
		uname -r | grep -q 5.0 || testcases+=" loop/001" # Fails on 5.0
		#testcases+=" loop/002" # Fails randomly on x86_64
		testcases+=" loop/003"
		#testcases+=" loop/004" # Fails randomly on powerpc
		testcases+=" loop/005"
	elif rlIsRHEL 9 || rlIsFedora || rlIsCentOS 9; then
		testcases+=" loop/001"
		testcases+=" loop/002"
		testcases+=" loop/003"
		testcases+=" loop/004"
		testcases+=" loop/005"
		testcases+=" loop/006"
		testcases+=" loop/007"
		testcases+=" loop/008"
		uname -ri | grep -Eq "el9_1|el9_2" || testcases+=" loop/009"
	fi

	echo "$testcases"
}

function get_test_cases_nvme
{
	typeset testcases=""

	if rlIsRHEL 7; then
		testcases+=" nvme/004"
		testcases+=" nvme/006"
		testcases+=" nvme/008"
		uname -ri | grep -q "3.10.0" || testcases+=" nvme/012"
		uname -ri | grep -qE "3.10.0-.*ppc64$|3.10.0-.*s390x" || testcases+=" nvme/014"
		uname -ri | grep -qE "3.10.0-.*ppc64$|3.10.0-.*s390x" || testcases+=" nvme/016"
		uname -ri | grep -q "3.10.0-.*s390x" || testcases+=" nvme/019"
		testcases+=" nvme/023"
		uname -ri | grep -qE "3.10.0-327|3.10.0-514|3.10.0-693" && testcases=""
		uname -ri | grep -qE "3.10.0-862" && testcases=" nvme/006"
	elif rlIsRHEL 8; then
		#testcases+=" nvme/002" #disable
		#testcases+=" nvme/003" #disable
		uname -ri | grep -qE "4.18.0-.*ppc64le" || testcases+=" nvme/004"
		#testcases+=" nvme/005" modprobe/modprobe -r nvme-core will be failed
		testcases+=" nvme/006"
		testcases+=" nvme/007"
		uname -ri | grep -qE "4.18.0-.*ppc64le" || testcases+=" nvme/008"
		testcases+=" nvme/009"
		uname -ri | grep -q "5\..*s390x" || testcases+=" nvme/010"
		uname -r | grep -Eq "5\.|4.18.0" || testcases+=" nvme/011"
		uname -ri | grep -Eq "4.18.0-80|5\..*s390x" || testcases+=" nvme/012"
		uname -r | grep -qE "5\.|4.18.0" || testcases+=" nvme/013"
		testcases+=" nvme/014"
		uname -r | grep -qE "5\.|4.18.0" || testcases+=" nvme/015"
		#testcases+=" nvme/016" #disable
		#testcases+=" nvme/017" #disable
		testcases+=" nvme/019"
		testcases+=" nvme/020"
		testcases+=" nvme/021"
		testcases+=" nvme/022"
		testcases+=" nvme/023"
		testcases+=" nvme/024"
		testcases+=" nvme/026"
		testcases+=" nvme/027"
		testcases+=" nvme/028"
	elif rlIsRHEL 9 || rlIsFedora || rlIsCentOS 9; then
		testcases+=" nvme/002"
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
		testcases+=" nvme/016"
		testcases+=" nvme/017"
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
	fi

	echo "$testcases"
}

function get_test_cases_scsi
{
	typeset testcases=""

	testcases+=" scsi/004"
	testcases+=" scsi/005"
	testcases+=" scsi/007"

	echo "$testcases"
}

function get_test_cases_zbd
{
	typeset testcases=""

	testcases+=" zbd/001"
	testcases+=" zbd/002"
	testcases+=" zbd/003"
	testcases+=" zbd/004"
	testcases+=" zbd/005"
	testcases+=" zbd/006"
	uname -ri | grep -q "el9_0" || testcases+=" zbd/008"

	echo "$testcases"
}

function main
{
	testcases_default=""
	testcases_default+=" $(get_test_cases_block)"
	testcases_default+=" $(get_test_cases_loop)"
	if ! rlIsRHEL 7; then
		testcases_default+=" $(get_test_cases_nvme)"
		testcases_default+=" $(get_test_cases_scsi)"
	fi
	if rlIsRHEL 9 || rlIsFedora || rlIsCentOS 9; then
		testcases_default+=" $(get_test_cases_zbd)"
	fi
	testcases=${_DEBUG_MODE_TESTCASES:-"$testcases_default"}
	test_ws=./blktests
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

	. "$CDIR"/build.sh

	main
fi
