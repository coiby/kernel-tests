#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
source "$CDIR"/../../../cki_lib/libcki.sh || exit 1

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

function get_test_result
{
	typeset test_ws=$1
	typeset test_case=$2

	typeset result_dir="$test_ws/results"
	result_file="$(find "$result_dir" -type f | grep -E "$test_case$")"
	typeset out_bad_file="${result_file}.out.bad"
	typeset out_full_file="${result_file}.full"
	typeset out_dmesg_file="${result_file}.dmesg"
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
