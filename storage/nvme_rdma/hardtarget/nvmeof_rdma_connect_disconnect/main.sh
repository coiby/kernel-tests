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
	while [ $num -lt $test_num ]
	do
		tlog "INFO: connect-disconnect operation:$num"

		NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP0" "$HostNQN1"
		NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP1" "$HostNQN2"

		tok "sleep 0.5"
		tok nvme list
		tok lsblk
		nvme_devs=$(nvme list | grep -oE nvme.n.)
		tlog "INFO: start dd background operation on $nvme_devs"
		for nvme_dev in $nvme_devs; do
			tok "dd if=/dev/${nvme_dev} of=/dev/null bs=4M count=1024" &
		done
		wait

		# shellcheck disable=SC2154
		tok "nvme disconnect -n $TargetNQN"
		ret=$?
		if [ $ret -eq 0 ]; then
			tlog "INFO: disconnect target pass"
		else
			tlog "INFO: connect to tartet failed"
			break
		fi
		tok "sleep 0.5"
		((num++))
	done

	if [ $ret -ne 0 ]; then
		tlog "INFO: nvme disconnect target failed at iteration:$num"
	else
		tlog "INFO: nvme disconnect target pass"
	fi
}

tlog "running $0"
trun "uname -a"
runtest
tend

