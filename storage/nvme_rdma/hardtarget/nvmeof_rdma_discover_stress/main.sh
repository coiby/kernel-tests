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
	while [ $num -lt $test_num ]
	do
		tlog "INFO: stress discvover operation:$num"

		tok "nvme discover -t rdma -a $IP0"
		tok "nvme discover -t rdma -a $IP1"

		((num++))
	done
}

tlog "running $0"
trun "uname -a"
runtest
tend

