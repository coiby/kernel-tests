#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 200

# Print the system info
system_info_for_debug

function runtest {

	HostNQN=nvme-rdma-host-1-nqn-1
	tok "nvme discover -t rdma -a $IP0"
	tok "nvme discover -t rdma -a $IP1"
	tlog "INFO: start to connect with invalid nqn"
	tnot "nvme connect -t rdma -a $IP0 -n testnqn -q $HostNQN"
	tnot "nvme connect -t rdma -a $IP1 -n testnqn -q $HostNQN"
}

tlog "running $0"
trun "uname -a"
runtest
tend
