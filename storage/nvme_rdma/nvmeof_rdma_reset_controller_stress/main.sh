#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

echo Servers: $SERVERS
echo Clients: $CLIENTS

# start the subnet manager
start_sm

function client {
	tlog "--- wait server to set SERVER_NVMEOF_RDMA_TARGET_SETUP_READY ---"
	rstrnt-sync-block -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" ${SERVERS}

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
	tok "nvme connect -t rdma -a $target_ip -s 4420 -n testnqn"
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

	#update nvme sysfs
	if realpath /sys/block/$nvme_device | grep -o nvme-subsystem; then
		sysfs="/sys/block/${nvme_device}/device/nvme*"
	else
		sysfs="/sys/block/${nvme_device}/device"
	fi

	#stress reset_controller operation
	tlog "INFO: start reset_controller operation"
	test_num=200
	num=0
	while [ $num -lt $test_num ];
	do
		tok "echo 1 > ${sysfs}/reset_controller"
		ret=$?
		if [ $ret -eq 1 ]; then
			tlog "INFO: reset_controller operation failed: $num"
			break
		fi
		((num++))
		sleep 0.2
	done
	[ $ret -eq 0 ] && tlog "INFO: reset_controller operation pass:$num"

	rstrnt-sync-set -s "CLIENT_RESET_CONTROLLER_DONE"

	#disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	rstrnt-sync-set -s "CLIENT_DISCONECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP $test_protocol
	if [ $? -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rstrnt-sync-set -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set CLIENT_RESET_CONTROLLER_DONE ---"
	rstrnt-sync-block -s "CLIENT_RESET_CONTROLLER_DONE" ${CLIENTS}

	tlog "--- wait client to set CLIENT_DISCONECT_TARGET_DONE ---"
	rstrnt-sync-block -s "CLIENT_DISCONECT_TARGET_DONE" ${CLIENTS}

	# Clear target
	tok nvmetcli clear
	if [ $? -ne 0 ]; then
		tlog "INFO: nvmetcli clear failed"
		return 1
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
