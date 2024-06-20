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
	tok nvme list-subsys
	tok lsblk


	#reset_controller operation
	nvme_devs=$(nvme list | grep -oE nvme.n.)
	tlog "INFO: start rescan/reset controller operation"
	test_num=100
	num=0
	while [ $num -lt $test_num ];
	do
		for nvme_dev in $nvme_devs; do
			#update nvme sysfs
			if realpath /sys/block/"$nvme_dev" | grep -qo nvme-subsystem; then
				sysfs="/sys/block/${nvme_dev}/device/${nvme_dev:0:5}"
			else
				sysfs="/sys/block/${nvme_dev}/device"
			fi
			tok "echo 1 > ${sysfs}/reset_controller"
			ret=$?
			if [ $ret -ne 0 ]; then
				tlog "FAIL: reset_controller on $nvme_dev failed: $num"
			fi
			sleep 0.1
		done
		((num++))
		sleep 0.1
	done
	[ $ret -eq 0 ] && tlog "INFO: reset_controller operation pass:$num"

	tok nvme disconnect-all
}

tlog "running $0"
trun "uname -a"
runtest
tend

