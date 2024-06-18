#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 200

# Print the system info
system_info_for_debug

function runtest {

	#install fio tool
	install_fio
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "INFO: fio install failed"
		return 1
	else
		tlog "INFO: fio install pass"
	fi

	# connect to E5700
	HostNQN1=nvme-rdma-host-1-nqn-1
	HostNQN2=nvme-rdma-host-2-nqn-1
	HostID1=$(uuid)
	HostID2=$(uuid)

	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP0" "$HostNQN1" "$HostID1"
	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP1" "$HostNQN2" "$HostID2"

	tok "sleep 1.5"
	tok nvme list
	tok lsblk
	nvme_devs=$(nvme list | grep -oE nvme.n.)
	tlog "INFO: start fio background operation on $nvme_devs"
	for nvme_dev in $nvme_devs; do
		FIO_Device_Level_Test "$nvme_dev" &
	done

	# wait background fio operation done
	tlog "INFO: wait fio background operation on $nvme_devs"
	wait
	tlog "INFO: fio background operation on $nvme_devs done"

	tok nvme disconnect-all
}

tlog "running $0"
trun "uname -a"
runtest
tend
