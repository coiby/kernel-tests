#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
source $CDIR/../../../cki_lib/libcki.sh || exit 1

function disable_multipath
{
	pidof multipathd &>/dev/null && pkill -9 multipathd
	[ -f /etc/multipath.conf ] && rm -f /etc/multipath.conf
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
	typeset result_file="$(find "$result_dir" -type f | grep -E "$test_case$")"
	typeset out_bad_file="${result_file}.out.bad"
	typeset out_full_file="${result_file}.full"
	typeset out_dmesg_file="${result_file}.dmesg"
	typeset result="UNTESTED"
	if [[ -n $result_file ]]; then
		typeset res="$(grep "^status" $result_file)"
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
