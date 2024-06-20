#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 200

# Print the system info
system_info_for_debug

function runtest {

	num=0
	test_num=100
	HostNQN1=nvme-rdma-host-1-nqn-1
	HostNQN2=nvme-rdma-host-2-nqn-1
	HostID1=$(uuid)
	HostID2=$(uuid)

	while [ $num -lt $test_num ]
	do
		tlog "INFO: connect delete_controller operation:$num"

		NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP0" "$HostNQN1" "$HostID1"
		NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP1" "$HostNQN2" "$HostID2"

		tok "sleep 1.5"
		tok lsblk
		tok nvme list

		nvme_subsys=$(nvme list-subsys | grep -oE "nvme[0-9]")
		for nvme_sub in $nvme_subsys; do
			tok "echo 1 > /sys/class/nvme/$nvme_sub/delete_controller"
			ret=$?
			if (( ret == 0 )); then
				tlog "INFO: delete controller:$nvme_sub pass"
			else
				tlog "INFO: delete controller:$nvme_sub failed"
				break
			fi
		done
		tok "sleep 2"
		((num++))
	done
	if (( ret != 0 )); then
		tlog "INFO: nvme connect/delete_controller:$nvme_sub failed at iteration:$num"
	else
		tlog "INFO: nvme connect/delete_controller $nvme_sub pass"
	fi
}

tlog "running $0"
trun "uname -a"
runtest
tend
