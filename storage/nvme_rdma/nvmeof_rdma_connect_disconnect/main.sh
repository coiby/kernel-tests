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
		tlog "INFO: connect-disconnect operation:$num"
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
		nvme_device=`lsblk | grep -o nvme.n. | sort | tail -1`
#		nvme disconnect -d /dev/${nvme_device}
		tok "dd if=/dev/"$nvme_device" of=/dev/null bs=4M count=1024"
		trun "nvme disconnect -n testnqn"
		ret=$?
		if [ $ret -eq 0 ]; then
			tlog "INFO: disconnect target pass"
		else
			tlog "INFO: connect to tartet failed"
			break
		fi
		tok "sleep 2"
		((num++))
	done

	if [ $ret -ne 0 ]; then
		tlog "INFO: nvme disconnect $nvme_device failed"
	else
		tlog "INFO: nvme disconnect $nvme_device pass"
	fi
	rstrnt-sync-set -s "CLIENT_CONNECT_DISCONECT_TARGET_DONE"
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

	tlog "--- wait client to set CLIENT_CONNECT_DISCONECT_TARGET_DONE---"
	rstrnt-sync-block -s "CLIENT_CONNECT_DISCONECT_TARGET_DONE" ${CLIENTS}

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

# Print the system info
system_info_for_debug

tend
