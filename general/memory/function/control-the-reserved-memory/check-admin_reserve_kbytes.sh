#!/bin/bash
#
# Description
# The amount of free memory in the system that should be reserved for users
# with the capability cap_sys_admin.
#
# admin_reserve_kbytes defaults to min(3% of free pages, 8MB)
#
# That should provide enough for the admin to log in and kill a process,
# if necessary, under the default overcommit 'guess' mode.
#
# Systems running under overcommit 'never' should increase this to account
# for the full Virtual Memory Size of programs used to recover. Otherwise,
# root may not be able to log in to recover the system.

TEST_SUCCESS=true

if [ -f "/proc/sys/vm/admin_reserve_kbytes" ]; then
	ADMIN_RESERVE_KBYTES=`/bin/cat /proc/sys/vm/admin_reserve_kbytes`

	# check the default valuse
	if [ $ADMIN_RESERVE_KBYTES -le 8192 ]; then
		echo "admin_reserve_kbytes = $ADMIN_RESERVE_KBYTES"
	else
		echo "admin_reserve_kbytes = $ADMIN_RESERVE_KBYTESL"
		TEST_SUCCESS=false
	fi

	# change the size
	for new_size in 0 1024 80192; do
		echo $new_size > /proc/sys/vm/admin_reserve_kbytes	  || TEST_SUCCESS=false
	done
	echo $ADMIN_RESERVE_KBYTES > /proc/sys/vm/admin_reserve_kbytes	  || TEST_SUCCESS=false

	# check if test PASS
	if $TEST_SUCCESS; then
		echo "finished running the test. PASS"
		exit 0;
	else
		echo "please check log message. FAIL"
		exit 1;
	fi

else
	echo "admin_reserve_kbytes is not exsit, system does not support the feature"
	exit 2;
fi
