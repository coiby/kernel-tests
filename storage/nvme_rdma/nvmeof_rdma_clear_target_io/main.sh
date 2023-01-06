#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

echo Servers: $SERVERS
echo Clients: $CLIENTS

# Print the system info
system_info_for_debug

# start the subnet manager
start_sm

function client {

	tlog "--- wait server to set SERVER_NVMEOF_RDMA_TARGET_SETUP_READY_1 ---"
	rhts_sync_block -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY_1" ${SERVERS}

	#install fio tool
	install_fio
	if [ $? -ne 0 ]; then
		tlog "INFO: fio install failed"
		return 1
	else
		tlog "INFO: fio install pass"
	fi

	# Get RDMA testing protocol target IP
	NVMEOF_RDMA_TARGET_IP $test_protocol
	target_ip=$RETURN_STR

	# Connect to target
	tok "nvme connect-all -t rdma -a $target_ip -s 4420"
	if [ $? -ne 0 ]; then
		tlog "INFO: failed to connect to target:$target_ip"
		return 1
	else
		tlog "INFO: connected to target:$target_ip"
	fi

	tok "sleep 1.5"
	lsblk
	nvme_device=`lsblk | grep -o nvme.n. | sort | tail -1`
	tlog "INFO: will use $nvme_device for testing"

	#fio basic device level testing
	FIO_Basic_Device_Level_Test "$nvme_device"

	rhts_sync_set -s "CLIENT_FIO_RUNNING"

	tlog "--- wait server to set SERVER_TARGET_CLEAR_DONE ---"
	rhts_sync_block -s "SERVER_TARGET_CLEAR_DONE" ${SERVERS}

	tlog "--- wait server to set SERVER_NVMEOF_RDMA_TARGET_SETUP_READY_2 ---"
	rhts_sync_block -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY_2" ${SERVERS}

	sleep 30

	# wait background fio operation done
	tlog "INFO: wait fio operation done"
	wait

	#disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	rhts_sync_set -s "CLIENT_DISCONECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP $test_protocol
	if [ $? -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rhts_sync_set -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY_1"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set  CLIENT_FIO_RUNNING---"
	rhts_sync_block -s "CLIENT_FIO_RUNNING" ${CLIENTS}

	# clear target
	tok "nvmetcli clear"
	if [ $? -ne 0 ]; then
		tlog "INFO: nvmetcli clear failed"
		return 1
	else
		tlog "INFO: nvmetcli clear pass"
		rhts_sync_set -s "SERVER_TARGET_CLEAR_DONE"
	fi

	sleep 5

	# setup target
	NVMEOF_RDMA_TARGET_SETUP $test_protocol
	if [ $? -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rhts_sync_set -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY_2"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set CLIENT_DISCONECT_TARGET_DONE ---"
	rhts_sync_block -s "CLIENT_DISCONECT_TARGET_DONE" ${CLIENTS}

	# Clear target
	tok "nvmetcli clear"
	if [ $? -ne 0 ]; then
		tlog "INFO: nvmetcli clear failed"
	else
		tlog "INFO: nvmetcli clear pass"
	fi
}

# Start test
#####################################################################

# start client and server tests
if hostname -A | grep ${CLIENTS%%.*} >/dev/null ; then
	echo "------- client start test -------"
	TEST=${TEST}/client
	client
fi

if hostname -A | grep ${SERVERS%%.*} >/dev/null ; then
	echo "------- server is ready -------"
	TEST=${TEST}/server
	server
fi

tend
