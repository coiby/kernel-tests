#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

echo Servers: "$SERVERS"
echo Clients: "$CLIENTS"

# start the subnet manager
start_sm

# Print the system info
system_info_for_debug

function client {
	tlog "--- wait server to set 18_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY ---"
	rstrnt-sync-block -s "18_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" "${SERVERS}"

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

	prepare_reboot

	tok "nvme discover -t rdma -a $target_ip"
	tok "nvme connect -t rdma -a $target_ip -s 4420 -n testnqn"
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "INFO: failed to connect to target:$target_ip"
		rstrnt-sync-set -s "18_CLIENT_DISCONECT_TARGET_DONE"
		return 1
	else
		tlog "INFO: connected to target:$target_ip"
	fi
	tok "sleep 1.5"
	tok lsblk
	nvme_device=$(lsblk | grep -o nvme.n. | sort | tail -1)
	tlog "Start $nvme_device io testing background"
	trun "fio -filename=/dev/\"$nvme_device\" -iodepth=64 -thread -rw=randwrite -ioengine=libaio -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=240 -time_based -size=1g -group_reporting -name=mytest -numjobs=64" &

	suspend_resume mem 180

	rstrnt-sync-set -s "18_CLIENT_CONNECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP "$test_protocol"
	ret=$?
	if [ $ret -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rstrnt-sync-set -s "18_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set 18_CLIENT_CONNECT_TARGET_DONE---"
	rstrnt-sync-block -s "18_CLIENT_CONNECT_TARGET_DONE" "${CLIENTS}"

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

tlog "running $0"
trun "uname -a"
tlog "REBOOTCOUNT=$REBOOTCOUNT"

if [ "$REBOOTCOUNT" -eq 0 ]; then
	add_kernel_option
elif [ "$REBOOTCOUNT" -eq 1 ]; then

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
else
	tlog "$0 test completed"
fi

tend
