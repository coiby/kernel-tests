#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

echo Servers: "$SERVERS"
echo Clients: "$CLIENTS"

# Print the system info
system_info_for_debug

# start the subnet manager
start_sm

function client {
	tlog "--- wait server to set 3_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY ---"
	rstrnt-sync-block -s "3_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" "${SERVERS}"

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

#	# Connect to target
#	tok "nvme connect-all -t rdma -a $target_ip -s 4420"
#	if [ $? -ne 0 ]; then
#		tlog "INFO: failed to connect to target:$target_ip"
#		return 1
#	else
#		tlog "INFO: connected to target:$target_ip"
#	fi

	num=0
	test_num=100
	while [ $num -lt $test_num ]
	do
		tlog "INFO: connect delete_controller operation:$num"
		tok "nvme discover -t rdma -a $target_ip"
		tok "nvme connect -t rdma -n testnqn -a $target_ip -s 4420"
		ret=$?
		if [ $ret -eq 0 ]; then
			tlog "INFO: connect to target pass"
		else
			tlog "INFO: connect to tartet failed"
			break
		fi
		tok "sleep 1.5"
		lsblk
		test_dev=$(lsblk | grep -o nvme. | sort | tail -1)
		if [ -n "$test_dev" ]; then
			tlog "INFO: got nvme disk:$test_dev"
		else
			tlog "INFO: got nvme disk:$test_dev failed"
			break
		fi
		tok "echo 1 > /sys/class/nvme/${test_dev}/delete_controller"
		ret=$?
		if [ $ret -eq 0 ]; then
			tlog "INFO: delete controller pass"
		else
			tlog "INFO: delete controller failed"
			break
		fi
		tok "sleep 2"
		((num++))
	done

	if [ $ret -ne 0 ]; then
		tlog "INFO: nvme connect/delete_controller $test_dev failed"
	else
		tlog "INFO: nvme connect/delete_controller $test_dev pass"
	fi

	rstrnt-sync-set -s "3_CLIENT_CONNECT_DELETE_CONTROLLER_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP "$test_protocol"
	ret=$?
	if [ $ret -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rstrnt-sync-set -s "3_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set 3_CLIENT_CONNECT_DELETE_CONTROLLER_DONE ---"
	rstrnt-sync-block -s "3_CLIENT_CONNECT_DELETE_CONTROLLER_DONE" "${CLIENTS}"

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
