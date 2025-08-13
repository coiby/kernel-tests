#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 200

# Print the system info
system_info_for_debug

function runtest {

	# connect to E5700 host nvme-rdma-host-1-nqn-1 which has 21 luns
	HostNQN1=nvme-rdma-host-9-nqn-1
	HostID1=$(uuid)
	num=0
	while [ $num -lt 10 ]; do
		tlog "Start to test nvme rdma luns mapping test:$num"

		NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP0" "$HostNQN1" "$HostID1"

		tok "sleep 1.5"
		tok nvme list
		tok lsblk
		tok nvme list-subsys
		tok nvme netapp smdevices
		tok "grep . /sys/block/nvme0n*/nsid >ns.info"
		local ns=1
		while [ $ns -lt 22 ]; do
			NSID=$((ns+20))
			tlog "Start to check nvme disk mapping for /dev/nvme0n$ns with nsid:$NSID"
			tok "cat ns.info | grep nvme0n$ns\/nsid:$NSID"
			if [ $? -ne 0 ]; then
				tlog "/dev/nvme0n$ns mapping for nsid:$NSID failed"
				trun "cat ns.info"
			fi
			((ns++))
		done

		tok nvme disconnect-all
		((num++))
	done
}

tlog "running $0"
trun "uname -a"
runtest
tend
