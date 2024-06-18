#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../../include/include.sh || exit 200

# Print the system info
system_info_for_debug

function runtest()
{
	nvme_core_multipath_conf enable

	# connect to E5700 target
	HostNQN=nvme-rdma-host-5-nqn-1
	HostID1=$(uuid)

	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP0" "$HostNQN" "$HostID1"
	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP1" "$HostNQN" "$HostID1"

	# wait 5s to wait connecting
	sleep 5

	nvme_dev=$(lsblk | grep -o nvme.n. | awk '++n==1')
	if [[ -n "$nvme_dev" ]]; then
		tlog "INFO: get nvme device: $nvme_dev"
	else
		tok lsblk
		tlog "FAIL: cannot get nvme disk"
		tok nvme disconnect-all
		nvme_core_multipath_conf disable
		return 1
	fi
	# Output native nvme multipath status
	tok nvme list
	tok nvme list-subsys
	tok nvme list-subsys /dev/"$nvme_dev"

	# Verify 1 optimized and 1 non-optimized paths
	optimized_paths=$(nvme list-subsys /dev/"$nvme_dev" | grep -c " optimized")
	if (( optimized_paths == 1)); then
		tlog "PASS: 1 NVMe Native Multipath path is optimized"
	else
		tlog "FAIL: 1 optimized path is expected"
	fi

	non_optimized_paths=$(nvme list-subsys /dev/"$nvme_dev" | grep -c "non-optimized")
	if (( non_optimized_paths == 1 )); then
		tlog "PASS: 1 NVMe Native Multipath path is non-optimized"
	else
		tlog "FAIL: 1 non-optimized path is expected"
	fi

	sleep 1.5

	#start FIO test
	tlog "INFO: Will use $nvme_dev for testing"
	FIO_Device_Level_Test "$nvme_dev"
	ret=$?
	if (( ret == 0 )); then
		tlog "PASS: fio testing on $nvme_dev passed"
	else
		tlog "FAIL: fio testing on $nvme_dev failed"
	fi

	# disconnect the target
	tok nvme disconnect-all

	# remove the native multipath configuration
	nvme_core_multipath_conf disable
}

tlog "running $0"
trun "uname -a"
runtest
tend

