#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function BLK_MQ_IO_SCHEDULER_IO() {

	mq_num=$1
for TEST_DISK in $TEST_DISKS; do
	Iozone_Multi_Process_Test "$TEST_DISK" "mq" "$mq_num" &
	if [ $? -ne 0 ]; then
		tlog "FAIL: Iozone_6_Process_Test for $TEST_DISK failed"
		return 1
	fi
done
wait

for TEST_DISK in $TEST_DISKS; do
	FIO_Device_Level_Test "$TEST_DISK" "mq" "$mq_num" &
	if [ $? -ne 0 ]; then
		tlog "FAIL: FIO_Device_Level_Test for $TEST_DISK failed"
		return 1
	fi
done
wait

for TEST_DISK in $TEST_DISKS; do
	DT_IO_Test_Device_Level "$TEST_DISK" "mq" "$mq_num" &
	if [ $? -ne 0 ]; then
		tlog "FAIL: DT_IO_Test_Device_Level for $TEST_DISK failed"
		return 1
	fi
done
wait

for TEST_DISK in $TEST_DISKS; do
	DT_IO_Test_File_Level "$TEST_DISK" "mq" "$mq_num" &
	if [ $? -ne 0 ]; then
		tlog "FAIL: DT_IO_Test_File_Level for $TEST_DISK failed"
		return 1
	fi
done
wait
}

function NVME_IO_SCHEDS_SWITCH_RESCAN_RESET() {
		for DISK in $DISKS; do
			nvme_pci_id="$(get_nvme_pci_id "$DISK")"
			MQ_IOSCHEDS="$(sed 's/[][]//g' /sys/block/"$DISK"/queue/scheduler)"
			for SCHEDULER in $MQ_IOSCHEDS; do
				tlog "BLK-MQ IO SCHEDULER:$SCHEDULER testing during IO on $DISK"
				echo "$SCHEDULER" > /sys/block/"$DISK"/queue/scheduler
				sleep .5
				echo 1 >/sys/bus/pci/devices/"$nvme_pci_id"/rescan
				echo 1 >/sys/bus/pci/devices/"$nvme_pci_id"/reset
				sleep .5
			done
		done
}
function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	install_fio

	install_iozone

	install_dt

	get_nvme_disk

	partition_1_primary "$DISKS"

	local mq_num=$(nproc)
	tlog "Will set mq_num=$mq_num during IO test"

	BLK_MQ_IO_SCHEDULER_IO "$mq_num" &>test.log &
	pid0=$!
	while kill -0 $pid0 2>/dev/null; do
		tlog "Will do NVME_IO_SCHEDS_SWITCH_RESCAN_RESET"
		NVME_IO_SCHEDS_SWITCH_RESCAN_RESET &
		pid1=$!
		tlog "pid1=$pid1, pid0=$pid0"
		while kill -0 $pid1 2>/dev/null; do
			echo "start offline" >>/root/log
			echo 0 > /sys/devices/system/cpu/cpu1/online
			echo 0 > /sys/devices/system/cpu/cpu2/online
			echo 0 > /sys/devices/system/cpu/cpu3/online
			sleep .5
			echo "start online" >>/root/log
			echo 1 > /sys/devices/system/cpu/cpu1/online
			echo 1 > /sys/devices/system/cpu/cpu2/online
			echo 1 > /sys/devices/system/cpu/cpu3/online
		done
	done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
