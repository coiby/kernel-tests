#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../../../cki_lib/libcki.sh || exit 1

# restraint uses $OUTPUTFILE by default when reporting test result.
# Let's save the test execution output to it.
if [ -z "$OUTPUTFILE" ]; then
	OUTPUTFILE=$(mktemp /mnt/testarea/tmp.XXXXXX)
fi

function disable_multipath
{
	pidof multipathd &>/dev/null && pkill -9 multipathd
	[ -f /etc/multipath.conf ] && rm -f /etc/multipath.conf
}

function enable_nvme_core_multipath
{
	modprobe nvme_core
	if [ -e "/sys/module/nvme_core/parameters/multipath" ]; then
		modprobe -qfr nvme_rdma nvme_fabrics nvme nvme_core
		echo "options nvme_core multipath=Y"  > /etc/modprobe.d/nvme.conf
		modprobe nvme
		#wait enough time for NVMe disk initialized
		sleep 5
	fi
}

function get_timestamp
{
	date +"%Y-%m-%d %H:%M:%S"
}

function do_test
{
	typeset test_ws=$1
	typeset test_case=$2

	typeset this_case=$test_ws/tests/$test_case
	echo ">>> $(get_timestamp) | Start to run test case $this_case ..."
	cd "$test_ws" || return 1
	./check "$test_case" | tee "${OUTPUTFILE}"
	echo ">>> $(get_timestamp) | End $this_case"
	return 0
}

function get_test_result
{
	typeset test_ws=$1
	typeset test_case=$2

	typeset result_dir="$test_ws/results"
	result_file="$(find "$result_dir" -type f | grep -E "$test_case$")"
	typeset out_bad_file="${result_file}.out.bad.log"
	typeset out_full_file="${result_file}.full.log"
	typeset out_dmesg_file="${result_file}.dmesg.log"
	typeset result="UNTESTED"
	if [[ -n $result_file ]]; then
		res=$(grep "^status" "$result_file")
		if [[ $res == *"pass" ]]; then
			result="PASS"
		elif [[ $res == *"fail" ]]; then
			result="FAIL"
			[ -f "$out_bad_file" ] && cki_upload_log_file "$out_bad_file" >/dev/null
			[ -f "$out_full_file" ] && cki_upload_log_file "$out_full_file" >/dev/null
			[ -f "$out_dmesg_file" ] && cki_upload_log_file "$out_dmesg_file" >/dev/null
		elif [[ $res == *"not run" ]]; then
			result="SKIP"
		else
			result="OTHER"
		fi
	fi

	echo $result
}

function report_test_result
{
	typeset result=$1
	typeset test_name=$2
	typeset -i ret=0
	if [[ $result == "PASS" ]]; then
		rstrnt-report-result "${test_name}" PASS 0
		ret=0
	elif [[ $result == "FAIL" ]]; then
		rstrnt-report-result "${test_name}" FAIL 1
		ret=1
	elif [[ $result == "SKIP" || $result == "UNTESTED" ]]; then
		rstrnt-report-result "${test_name}" SKIP 0
		ret=0
	else
		rstrnt-report-result "${test_name}" WARN 2
		ret=2
	fi
	return $ret
}
