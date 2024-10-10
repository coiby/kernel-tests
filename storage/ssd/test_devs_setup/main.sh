#!/bin/bash

FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
. $CDIR/../../include/bash_modules/lxt/include.sh || exit 200

TEST_DEVS=${TEST_DEVS:-""}
TEST_DEVS_LIST=${TEST_DEVS_LIST:-""}

ROOT_DISK=$(get_root_disk)

if [ -z "$TEST_DEVS" ]; then
	lsblk | grep -wo nvme.n. | while read -r dev; do
		if [[ "$ROOT_DISK" == "$dev" ]]; then
			continue
		else
			TEST_DEVS+="$dev "
		fi

	done
fi

if [ -z "$TEST_DEVS" ]; then
	tlog "Abort test as no TEST_DEVS avaiable for testing"
	rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
	exit 0
fi
TEST_DEVS_TMP="$TEST_DEVS"
for dev in $TEST_DEVS_TMP; do
	if [[ "$ROOT_DISK" == "$dev" ]]; then
		TEST_DEVS=${TEST_DEVS/$ROOT_DISK/}
	fi
done
if [ -z "$TEST_DEVS_LIST" ]; then
	for dev in $TEST_DEVS; do
		TEST_DEVS_LIST+="/dev/$dev "
		tok "wipefs -a /dev/$dev"
	done
fi

tok partprobe
tok udevadm settle

#Save TEST_DEVS TEST_DEV_LIST to files
tok "echo ROOT_DISK:$ROOT_DISK"
tok "echo $TEST_DEVS >/root/TEST_DEVS"
tok "echo $TEST_DEVS_LIST >/root/TEST_DEVS_LIST"
tend
