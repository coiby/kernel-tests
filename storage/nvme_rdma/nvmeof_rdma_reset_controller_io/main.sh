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
	tlog "--- wait server to set 13_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY ---"
	rstrnt-sync-block -s "13_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" "${SERVERS}"

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

	#update nvme sysfs
	if realpath /sys/block/"$nvme_device" | grep -o nvme-subsystem; then
		sysfs="/sys/block/${nvme_device}/device/nvme*"
	else
		sysfs="/sys/block/${nvme_device}/device"
	fi

	#fio basic device level testing
	FIO_Basic_Device_Level_Test "$nvme_device"

	#reset_controller operation
	tlog "INFO: Start reset_controller operation"
	num=0
	test_num=100
	while [ $num -lt $test_num ];
	do
		tok "echo 1 > ${sysfs}/reset_controller"
		ret=$?
		if [ $ret -eq 1 ]; then
			tlog "INFO: reset_controller operation failed: $num"
			break
		fi
		((num++))
		sleep 0.5
	done
	[ $ret -eq 0 ] && tlog "INFO: reset_controller operation pass:$num"

	# wait background fio operation done
	tlog "INFO: wait fio operation done"
	wait

	rstrnt-sync-set -s "13_CLIENT_FIO_RESET_CONTROLLER_DONE"

	#disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	rstrnt-sync-set -s "13_CLIENT_DISCONECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP "$test_protocol"
	ret=$?
	if [ $ret -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rstrnt-sync-set -s "13_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set 13_CLIENT_FIO_RESET_CONTROLLER_DONE ---"
	rstrnt-sync-block -s "13_CLIENT_FIO_RESET_CONTROLLER_DONE" "${CLIENTS}"
	tlog "--- wait client to set 13_CLIENT_DISCONECT_TARGET_DONE ---"
	rstrnt-sync-block -s "13_CLIENT_DISCONECT_TARGET_DONE" "${CLIENTS}"

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
