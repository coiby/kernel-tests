#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname $FILE)
. $CDIR/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	get_nvme_disk

	partition_1_primary "$DISKS"

for TEST_DISK in $TEST_DDISKS; do

	tok "dd if=/dev/$TEST_DISK of=/dev/null bs=1M count=10240"
	if [ $? -ne 0 ]; then
		tlog "dd read operation failed on $TEST_DISK"
		rstrnt-report-result "dd read on $TEST_DISK" "FAIL"
	fi
	tok "dd if=/dev/zero of=/dev/$DISK bs=1M count=10240"
	if [ $? -ne 0 ]; then
		tlog "dd write operation failed on $TEST_DISK"
		rstrnt-report-result "dd write on $TEST_DISK" "FAIL"
	fi
done
}

tlog "running $0"
trun "uname -a"

if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq "0" ]; then
	tlog "REBOOT_COUNT:$RSTRNT_REBOOTCOUNT"
	runtest
	sync
	tmt-reboot || rstrnt-reboot || rhts-reboot
elif [ "${RSTRNT_REBOOTCOUNT}" -lt 50 ]; then
	tlog "REBOOT_COUNT:$RSTRNT_REBOOTCOUNT"
	runtest
	report_result
	sync
	tmt-reboot || rstrnt-reboot || rhts-reboot
elif [ "$RSTRNT_REBOOTCOUNT" -eq 50 ]; then
	tlog "REBOOT_COUNT:$RSTRNT_REBOOTCOUNT, test done"
	sync
fi
tend
