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
	tlog "--- wait server to set 1_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY ---"
	rstrnt-sync-block -s "1_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" "$SERVERS"

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

	#nvme-cli sanity
	tok "yum -y install asciidoc xmlto systemd-devel libuuid-devel yum-utils libnvme-devel libnvme gcc-c++ meson rpm-build --skip-broken"
	tok "yumdownloader --source nvme-cli"
	tok "rpm -ivh nvme-cli-*el*.src.rpm"
	tok "rpmbuild -ba /root/rpmbuild/SPECS/nvme-cli.spec"
	tok "yum -y remove nvme-cli"
	tok "yum -y install nvme-cli"

	rstrnt-sync-set -s "1_CLIENT_NVMECLI_SANITY_DONE"

	tlog "--- wait server to set 1_SERVER_NVMETCLI_SANITY_DONE ---"
	rstrnt-sync-block -s "1_SERVER_NVMETCLI_SANITY_DONE" "${SERVERS}"

	#disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	rstrnt-sync-set -s "1_CLIENT_DISCONECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP "$test_protocol"
	ret=$?
	if [ $ret -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rstrnt-sync-set -s "1_SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set 1_CLIENT_NVMECLI_SANITY_DONE ---"
	rstrnt-sync-block -s "1_CLIENT_NVMECLI_SANITY_DONE" "$CLIENTS"

	#nvmetcli sanity
	tok "yum -y install asciidoc xmlto systemd-devel libuuid-devel yum-utils"
	if rlIsRHEL ">7"; then
		tok "yum -y install python3-devel python3-setuptools --nobest --skip-broken"
	else
		tok "yum -y install python-devel --skip-broken"
	fi
	tok "yumdownloader --source nvmetcli"
	tok "rpm -ivh nvmetcli-*el*.src.rpm"
	tok "rpmbuild -ba /root/rpmbuild/SPECS/nvmetcli.spec"
	tok "yum -y remove nvmetcli"
	tok "yum -y install nvmetcli"

	rstrnt-sync-set -s "1_SERVER_NVMETCLI_SANITY_DONE"

	tlog "--- wait client to set 1_CLIENT_DISCONECT_TARGET_DONE ---"
	rstrnt-sync-block -s "1_CLIENT_DISCONECT_TARGET_DONE" "$CLIENTS"

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
