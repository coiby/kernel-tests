#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	install_fio

	install_iozone

	install_dt

	get_nvme_disk

	partition_1_primary "$DISKS"

	mq_num=$(nproc)

for TEST_DISK in $TEST_DISKS; do
	{
	Iozone_Multi_Process_Test "$TEST_DISK" "mq" "$mq_num"
	if [ $? -ne 0 ]; then
		tlog "FAIL: Iozone_6_Process_Test for $TEST_DISK failed"
		return 1
	fi
	} &
done
wait

for TEST_DISK in $TEST_DISKS; do
	{
	FIO_Device_Level_Test "$TEST_DISK" "mq" "$mq_num"
	if [ $? -ne 0 ]; then
		tlog "FAIL: FIO_Device_Level_Test for $TEST_DISK failed"
		return 1
	fi
	} &
done
wait

for TEST_DISK in $TEST_DISKS; do
	{
	DT_IO_Test_Device_Level "$TEST_DISK" "mq" "$mq_num"
	if [ $? -ne 0 ]; then
		tlog "FAIL: DT_IO_Test_Device_Level for $TEST_DISK failed"
		return 1
	fi
	} &
done
wait

for TEST_DISK in $TEST_DISKS; do
	{
	DT_IO_Test_File_Level "$TEST_DISK" "mq" "$mq_num"
	if [ $? -ne 0 ]; then
		tlog "FAIL: DT_IO_Test_File_Level for $TEST_DISK failed"
		return 1
	fi
	} &
done
wait
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
