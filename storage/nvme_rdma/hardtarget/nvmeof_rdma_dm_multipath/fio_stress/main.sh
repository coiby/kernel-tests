#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../../include/include.sh || exit 200

# Print the system info
system_info_for_debug

function runtest()
{
	nvme_core_multipath_conf disable
	dm_multipath_conf enable

	# connect to E5700 target
	HostNQN=nvme-rdma-host-5-nqn-1
	HostID1=$(uuid)

	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP0" "$HostNQN" "$HostID1"
	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP1" "$HostNQN" "$HostID1"

	# wait 5s to wait connecting
	sleep 1.5

	nvme_dev=$(lsblk | grep -o nvme.n. | awk '++n==1')
	if [[ -n "$nvme_dev" ]]; then
		tlog "INFO: get nvme device: $nvme_dev"
	else
		tok lsblk
		tlog "FAIL: cannot get nvme disk"
		tok nvme disconnect-all
		dm_multipath_conf disable
		return 1
	fi
	nvme_dm_mpath_device=$(multipath -ll | grep "NetApp E-Series" | awk '{print $1}')
	if [[ -n "$nvme_dev" ]]; then
		tlog "INFO: get nvme dm_mpath device: $nvme_dm_mpath_device"
	else
		tok lsblk
		tlog "FAIL: cannot get nvme dm_mpath device"
		tok nvme disconnect-all
		dm_multipath_conf disable
		return 1
	fi

	# Output native nvme multipath status
	tok systemctl restart multipathd
	tok multipath -ll
	tok nvme list
	tok nvme list-subsys
	tok "nvme list-subsys /dev/$nvme_dev"

	# Verify 1 optimized and 1 non-optimized paths
	optimized_paths=$(nvme list-subsys /dev/"$nvme_dev" | grep -c " optimized")
	if (( optimized_paths == 1)); then
		tlog "PASS: 1 nvme dm-multipath path optimized"
	else
		tlog "FAIL: 1 nvme dm-multipath optimized path expected"
	fi

	non_optimized_paths=$(nvme list-subsys /dev/"$nvme_dev" | grep -c "non-optimized")
	if (( non_optimized_paths == 1 )); then
		tlog "PASS: 1 nvme dm-multipath path non-optimized"
	else
		tlog "FAIL: 1 nvme dm-multipath non-optimized path expected"
	fi

	mpath=$(multipath -ll | grep nvme | grep -c 'active ready running')
	if (( mpath == 2 )); then
		tlog "INFO: dm-mpath reports 2 active paths"
	else
		tlog "FAIL: dm-mpath reports $mpath active paths, which should be 2"
	fi

	#start FIO test
	tlog "INFO: Will use $nvme_dm_mpath_device for testing"
	FIO_Device_Level_Test "mapper/$nvme_dm_mpath_device"
	ret=$?
	if (( ret == 0 )); then
		tlog "PASS: fio testing on $nvme_dm_mpath_device passed"
	else
		tlog "FAIL: fio testing on $nvme_dm_mpath_device failed"
	fi

	# disconnect the target
	tok nvme disconnect-all

	# remove the dm-multipath configuration
	dm_multipath_conf disable
}

tlog "running $0"
trun "uname -a"
runtest
tend
