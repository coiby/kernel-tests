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
	tlog "--- wait server to set 8_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY ---"
	rstrnt-sync-block -s "8_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" "${SERVERS}"

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

	tok "nvme discover -t rdma -a $target_ip"
	tok "nvme connect -t rdma -n testnqn -a $target_ip -s 4420 --ctrl-loss-tmo=-1"
	if [[ "$(<"/sys/class/nvme/nvme0/ctrl_loss_tmo")" == off ]]; then
		tlog "nvme connect with --ctrl-loss-tmo=-1 works"
	else
		tlog "nvme connect with --ctrl-loss-tmo=-1 failed" "ERROR"
	fi

	#disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	tok "nvme connect -t rdma -n testnqn -a $target_ip -s 4420 --ctrl-loss-tmo=-2"
	if [[ "$(<"/sys/class/nvme/nvme0/ctrl_loss_tmo")" == off ]]; then
		tlog "nvme connect with --ctrl-loss-tmo=-2 works"
	else
		tlog "nvme connect with --ctrl-loss-tmo=-2 failed" "ERROR"
	fi

	#disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	rstrnt-sync-set -s "8_CLIENT_CONNECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP "$test_protocol"
	ret=$?
	if [ $ret -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rstrnt-sync-set -s "8_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set 8_CLIENT_CONNECT_TARGET_DONE---"
	rstrnt-sync-block -s "8_CLIENT_CONNECT_TARGET_DONE" "${CLIENTS}"

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

# Print the system info
system_info_for_debug

tend
