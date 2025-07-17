#!/bin/bash

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../include/include.sh || exit 200

# Print the system info
system_info_for_debug

function runtest {

	nvme_core_multipath_conf enable

	# connect to E5700 host nvme-rdma-host-5-nqn-1
	HostNQN1=nvme-rdma-host-5-nqn-1
	HostID1=$(uuid)

	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP0" "$HostNQN1" "$HostID1"
	NVMEOF_RDMA_TARGET_CONNECT_E5700 "$IP1" "$HostNQN1" "$HostID1"

	tok "sleep 1.5"
	tok lsblk
	tok nvme list
	tok nvme list-subsys
	tok nvme netapp smdevices
	test_dev=$(nvme list | grep "NetApp E-Series" | awk '{print $1}')
	if [[ -n "$test_dev" ]]; then
		tlog "INFO: get nvme device: $test_dev"
	else
		tok "lsblk"
		tlog "FAIL: cannot get nvme disk"
		tok nvme disconnect-all
		nvme_core_multipath_conf disable
		return 1
	fi
	tlog "NVMe Reservation: Register"
	tok "nvme resv-register ${test_dev} --nrkey=4 --rrega=0"
	tok "nvme resv-report ${test_dev}"

	tlog "NVMe Reservation: Replace"
	tok "nvme resv-register ${test_dev} --crkey=4 --nrkey=5 --rrega=2"
	tok "nvme resv-report ${test_dev}"

	tlog "NVMe Reservation: Unregister"
	tok "nvme resv-register ${test_dev} --crkey=5 --rrega=1"
	tok "nvme resv-report ${test_dev}"

	tlog "NVMe Reservation: Acquire"
	tok "nvme resv-register ${test_dev} --nrkey=4 --rrega=0"
	tok "nvme resv-acquire ${test_dev} --crkey=4 --rtype=1h --racqa=0"
	tok "nvme resv-report ${test_dev}"

	tlog "NVMe Reservation: Preempt"
	tok "nvme resv-acquire ${test_dev} --crkey=4 --rtype=2h --racqa=1 --prkey=4"
	tok "nvme resv-report ${test_dev}"

	tlog "NVMe Reservation: Release"
	tok "nvme resv-release ${test_dev} --crkey=4 --rtype=2h --rrela=0"
	tok "nvme resv-report ${test_dev}"

	tlog "NVMe Reservation: Clear"
	tok "nvme resv-acquire ${test_dev} --crkey=4 --rtype=1h --racqa=0"
	tok "nvme resv-report ${test_dev}"
	tok "nvme resv-release ${test_dev} --crkey=4 --rrela=1"
	tok "nvme resv-report ${test_dev}"

	tok "nvme disconnect-all"
}

tlog "running $0"
trun "uname -a"
runtest
tend
