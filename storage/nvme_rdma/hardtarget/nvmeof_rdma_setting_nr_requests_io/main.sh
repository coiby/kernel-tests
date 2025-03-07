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

	# fio basic device level testing
	nvme_devs=$(nvme list | grep -oE nvme.n.)
	tlog "INFO: start fio background operation on $nvme_devs"
	for nvme_dev in $nvme_devs; do
		FIO_Basic_Device_Level_Test "$nvme_dev"
	done

	if [[ "$(readlink -f "/sys/block/$nvme_dev/device")" =~ /nvme-subsystem/ ]]; then
		tlog "$nvme_devs are NVMe multipath devices"
		for nvme_multi in /sys/block/nvme*c*n*; do
			nr_num=$(cat /sys/block/"$nvme_multi"/queue/nr_requests)
			tok "echo 64 > $nvme_multi/queue/nr_requests"
			ret=$?
			if (( ret == 0 )); then
				tlog "INFO: setting nr_requests:64 on $nvme_multi pass"
			else
				tlog "INFO: setting nr_requests:64 on $nvme_multi failed"
			fi
		done
		# restore nr_requests
		tlog "INFO: restore nr_requests with $nr_num"
		for nvme_multi in /sys/block/nvme*c*n*; do
			tok "echo $nr_num > $nvme_multi/queue/nr_requests"
			ret=$?
			if (( ret == 0 )); then
				tlog "INFO: setting nr_requests:$nr_num on $nvme_multi pass"
			else
				tlog "INFO: setting nr_requests:$nr_num on $nvme_multi failed"
			fi
		done
	else
		nr_num=$(cat /sys/block/"$nvme_dev"/queue/nr_requests)
		for nvme_dev in $nvme_devs; do
			tok "echo 64 >/sys/block/${nvme_dev}/queue/nr_requests"
			ret=$?
			if (( ret == 0 )); then
				tlog "INFO: setting nr_requests:127 on $nvme_dev pass"
			else
				tlog "INFO: setting nr_requests:127 on $nvme_dev failed"
			fi
		done
		# restore nr_requests
		tlog "INFO: restore nr_requests with $nr_num"
		for nvme_dev in $nvme_devs; do
			tok "echo $nr_num >/sys/block/$nvme_dev/queue/nr_requests"
			ret=$?
			if [ $ret -eq 0 ]; then
				tlog "INFO: restore nr_requests:$nr_num on $nvme_dev pass"
			else
				tlog "INFO: setting nr_requests:$nr_num on $nvme_dev failed"
			fi
			trun cat /sys/block/"$nvme_dev"/queue/nr_requests
		done
	fi

	# wait background fio operation done
	tlog "INFO: wait fio background operation on $nvme_devs"
	wait
	tlog "INFO: fio background operation on $nvme_devs done"

	nvme disconnect-all
}

tlog "running $0"
trun "uname -a"
runtest
tend
