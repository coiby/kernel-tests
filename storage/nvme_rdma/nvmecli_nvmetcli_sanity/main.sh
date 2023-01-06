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
	rhts_sync_block -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY" ${SERVERS}

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

	#nvme-cli sanity
	tok "yum -y install asciidoc xmlto systemd-devel libuuid-devel yum-utils libnvme-devel libnvme gcc-c++ meson rpm-build --skip-broken"
	tok "yumdownloader --source nvme-cli"
	tok "rpm -ivh nvme-cli-*el*.src.rpm"
	tok "rpmbuild -ba /root/rpmbuild/SPECS/nvme-cli.spec"
	tok "yum -y remove nvme-cli"
	tok "yum -y install nvme-cli"

	rhts_sync_set -s "CLIENT_NVMECLI_SANITY_DONE"

	tlog "--- wait server to set SERVER_NVMETCLI_SANITY_DONE ---"
	rhts_sync_block -s "SERVER_NVMETCLI_SANITY_DONE" ${SERVERS}

	#disconnect the target
	NVMEOF_RDMA_DISCONNECT_TARGET n testnqn

	rhts_sync_set -s "CLIENT_DISCONECT_TARGET_DONE"
}

function server {

	NVMEOF_RDMA_TARGET_SETUP $test_protocol
	if [ $? -eq 0 ]; then
		# target set ready
		tlog "INFO: NVMEOF_RDMA_Target_Setup pass, test_protocol:$test_protocol"
		rhts_sync_set -s "SERVER_NVMEOF_RDMA_TARGET_SETUP_READY"
	else
		tlog "INFO: NVMEOF_RDMA_Target_Setup failed, test_protocol:$test_protocol"
		return 1
	fi

	tlog "--- wait client to set CLIENT_NVMECLI_SANITY_DONE ---"
	rhts_sync_block -s "CLIENT_NVMECLI_SANITY_DONE" ${CLIENTS}

	#nvmetcli sanity
	tok "yum -y install asciidoc xmlto systemd-devel libuuid-devel yum-utils"
	tok "uname -r | grep -q el8 && yum -y install python3-devel --nobest --skip-broken || yum -y install python-devel --skip-broken"
	tok "yumdownloader --source nvmetcli"
	tok "rpm -ivh nvmetcli-*el*.src.rpm"
	tok "rpmbuild -ba /root/rpmbuild/SPECS/nvmetcli.spec"
	tok "yum -y remove nvmetcli"
	tok "yum -y install nvmetcli"

	rhts_sync_set -s "SERVER_NVMETCLI_SANITY_DONE"

	tlog "--- wait client to set CLIENT_DISCONECT_TARGET_DONE ---"
	rhts_sync_block -s "CLIENT_DISCONECT_TARGET_DONE" ${CLIENTS}

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
