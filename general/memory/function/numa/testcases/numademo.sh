#!/bin/bash

numastat || exit 1
numastat -c || exit 1
numastat -m || exit 1
numastat -n || exit 1
if [ $(numactl -H | grep available | awk '{print $2}') -lt 2 ]; then
	exit 0
fi
numademo -t 32M memset memcpy forward backward stream random2 ptrchase || exit 1
exit 0
