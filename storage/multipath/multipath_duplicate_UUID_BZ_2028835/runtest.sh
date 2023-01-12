#!/bin/bash

FILE=$(readlink -f "$BASH_SOURCE")
CDIR=$(dirname "$FILE")

# Include enviroment and libraries
source "$CDIR"/../../../cki_lib/libcki.sh         || exit 1
. /usr/share/beakerlib/beakerlib.sh             || exit 1

function cleanup()
{
	service multipathd stop
	multipath -F
	yum -y remove device-mapper-multipath
	return 0

}

function run_test()
{
yum -y install device-mapper-multipath
rpm -qa | grep multipath
/sbin/mpathconf --enable
rm -rf /etc/multipath/wwids
service multipathd restart

rlRun "modprobe scsi_debug vpd_use_hostno=0 add_host=4 dev_size_mb=100"
rlRun "multipath -ll"
disk1=`rlRun 'multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==1"'`
echo "$disk1"
disk2=`rlRun 'multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==2"'`
echo "$disk2"
disk3=`rlRun 'multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==3"'`
echo "$disk3"
disk4=`rlRun 'multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==4"'`
echo "$disk4"
DM_MULTIPATH_DEVICE_PATH1=$(udevadm info -q property -n "$disk1" | grep DM_MULTIPATH_DEVICE_PATH)
echo "$DM_MULTIPATH_DEVICE_PATH1"
DM_MULTIPATH_DEVICE_PATH2=$(udevadm info -q property -n "$disk2" | grep DM_MULTIPATH_DEVICE_PATH)
echo "$DM_MULTIPATH_DEVICE_PATH2"
DM_MULTIPATH_DEVICE_PATH3=$(udevadm info -q property -n "$disk3" | grep DM_MULTIPATH_DEVICE_PATH)
echo "$DM_MULTIPATH_DEVICE_PATH3"
DM_MULTIPATH_DEVICE_PATH4=$(udevadm info -q property -n "$disk4" | grep DM_MULTIPATH_DEVICE_PATH)
echo "$DM_MULTIPATH_DEVICE_PATH4"


if [ -n "$DM_MULTIPATH_DEVICE_PATH1" ] && [ -n "$DM_MULTIPATH_DEVICE_PATH2" ] && [ -n "$DM_MULTIPATH_DEVICE_PATH3" ] && [ -n "$DM_MULTIPATH_DEVICE_PATH4" ];then
	rlPass "------- PASS,all paths always return: DM_MULTIPATH_DEVICE_PATH=1 ------"
	cleanup
	return 0
else
	rlFail "------- FAIL, not all paths always return: DM_MULTIPATH_DEVICE_PATH=1 -------"
	cleanup
	return 255
fi
}

rlJournalStart
	rlPhaseStartTest
		run_test
		value=$?
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
exit $value
