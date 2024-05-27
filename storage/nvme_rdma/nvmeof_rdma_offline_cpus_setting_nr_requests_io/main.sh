#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

echo Servers: "$SERVERS"
echo Clients: "$CLIENTS"

# start the subnet manager
start_sm

function client {
	tlog "--- wait server to set 11_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY ---"
	rstrnt-sync-block -s "11_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" "${SERVERS}"

	#install fio tool
	install_fio
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "INFO: fio install failed"
		return 1
	else
		tlog "INFO: fio install pass"
	fi

	# Get RDMA testing protocol target IP
	# shellcheck disable=SC2154
	NVMEOF_RDMA_TARGET_IP "$test_protocol"
	target_ip="$RETURN_STR"

	# Connect to target
	tok "nvme connect -t rdma -a $target_ip -s 4420 -n testnqn"
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "INFO: failed to connect to target:$target_ip"
		return 1
	else
		tlog "INFO: connected to target:$target_ip"
	fi
	tok "sleep 1.5"
	lsblk
	nvme_device=$(lsblk | grep -o nvme.n. | sort | tail -1)
	tlog "INFO: will use $nvme_device for testing"

	# fio basic device level testing
	FIO_Basic_Device_Level_Test "$nvme_device"

	# offline cpus
	tlog "INFO: start offline cpus"
	tok "echo 0 > /sys/devices/system/cpu/cpu1/online"
	tok "echo 0 > /sys/devices/system/cpu/cpu2/online"
	tok "echo 0 > /sys/devices/system/cpu/cpu3/online"

	nr_num=$(cat /sys/block/"$nvme_device"/queue/nr_requests)
	tok "echo 127 >/sys/block/${nvme_device}/queue/nr_requests"
	ret=$?
	if [ $ret -eq 0 ]; then
		tlog "INFO: setting nr_requests:127 operation pass"
	else
		tlog "INFO: setting nr_requests:127 operation failed"
	fi

	tlog "INFO: restore nr_requests with $nr_num"
	tok echo "$nr_num" >/sys/block/"$nvme_device"/queue/nr_requests
	ret=$?
	if [ $ret -eq 0 ]; then
		tlog "INFO: restore nr_requests:$nr_num operation pass"
	else
		tlog "INFO: setting nr_requests:$nr_num operation failed"
	fi
	trun cat /sys/block/"$nvme_device"/queue/nr_requests

	# online cpus
	tlog "INFO: start online cpus"
	tok "echo 1 > /sys/devices/system/cpu/cpu1/online"
	tok "echo 1 > /sys/devices/system/cpu/cpu2/online"
	tok "echo 1 > /sys/devices/system/cpu/cpu3/online"

	# wait background fio operation done
	tlog "INFO: wait fio operation done"
	wait

	rstrnt-sync-set -s "11_CLIENT_FIO_OFFLINE_CPUS_SETTING_NR_REQUESTS_DONE"

	# disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	rstrnt-sync-set -s "11_CLIENT_DISCONECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP "$test_protocol"
	ret=$?
	if [ $ret -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rstrnt-sync-set -s "11_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set 11_CLIENT_FIO_OFFLINE_CPUS_SETTING_NR_REQUESTS_DONE ---"
	rstrnt-sync-block -s "11_CLIENT_FIO_OFFLINE_CPUS_SETTING_NR_REQUESTS_DONE" "${CLIENTS}"
	tlog "--- wait client to set 11_CLIENT_DISCONECT_TARGET_DONE ---"
	rstrnt-sync-block -s "11_CLIENT_DISCONECT_TARGET_DONE" "${CLIENTS}"

	# Clear target
	tok nvmetcli clear
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "INFO: nvmetcli clear failed"
		return 1
	else
		tlog "INFO: nvmetcli clear pass"
	fi
}

# Start test
#####################################################################

# start client and server tests
if hostname -A | grep "${CLIENTS%%.*}" >/dev/null ; then
	echo "------- client start test -------"
	TEST="${TEST}"/client
	client
fi

if hostname -A | grep "${SERVERS%%.*}" >/dev/null ; then
	echo "------- server is ready -------"
	TEST="${TEST}"/server
	server
fi

tend
