#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
FILEC=$(readlink -f "${BASH_SOURCE[0]}")
CDIRC=$(dirname "$FILEC")
DCLIST="nvme/006 nvme/008 nvme/010 nvme/012 nvme/014 nvme/019 nvme/021 nvme/022 nvme/023 nvme/025 nvme/026 nvme/027 nvme/028"

source "$CDIRC"/../../../cki_lib/libcki.sh || exit 1

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
	echo ">>> $(get_timestamp) | Start to run test case $USE_RDMA $this_case ..."
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
	if rlIsRHEL ">9.4" || rlIsRHEL 10 || rlIsCentOS 10 || rlIsCentOS 9 || rlIsFedora; then
		if [[ "$DCLIST" =~ $test_case ]]; then
			result_dir="$test_ws/results/nodev_tr_${TRTYPE}_bd_${NVMET_BLKDEV_TYPE}"
		elif [[ "$test_case" =~ nvme ]]; then
			result_dir="$test_ws/results/nodev_tr_${TRTYPE}"
		fi
	fi
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

function get_test_cases_list
{
	typeset case_type=$1
	release=$(grep -o "release [0-9]*\.[0-9]*" /etc/redhat-release | awk '{print $2}')
	case_conf="$CDIRC/../config/$release"
	if rlIsFedora; then
		case_conf="$CDIRC/../config/fedora"
	elif rlIsCentOS "9"; then
		case_conf="$CDIRC/../config/c9s"
	elif rlIsCentOS "10"; then
		case_conf="$CDIRC/../config/c10s"
	fi
	if [ ! -f "$case_conf" ]; then
		if rlIsRHEL; then
			case_conf="$CDIRC/../config/defconf"
		else
			return
		fi
	fi
	# shellcheck disable=SC1090
	source "$case_conf"
	case_list=$(eval echo '$'"$case_type")
	echo "$case_list"
}
