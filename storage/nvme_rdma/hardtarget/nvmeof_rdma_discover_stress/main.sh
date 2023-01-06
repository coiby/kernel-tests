#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "$BASH_SOURCE")
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
		tlog "INFO: stress discvover operation:$num"

		tok nvme discover -t rdma -a $IP0
		tok nvme discover -t rdma -a $IP1

		((num++))
	done
}

tlog "running $0"
trun "uname -a"
runtest
tend

