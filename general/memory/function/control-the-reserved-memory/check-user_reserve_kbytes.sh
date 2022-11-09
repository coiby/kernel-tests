#!/bin/bash
#
# Description
# - user_reserve_kbytes
#
# When overcommit_memory is set to 2, "never overommit" mode, reserve
# min(3% of current process size, user_reserve_kbytes) of free memory.
# This is intended to prevent a user from starting a single memory hogging
# process, such that they cannot recover (kill the hog).
#
# user_reserve_kbytes defaults to min(3% of the current process size, 128MB).
#
# If this is reduced to zero, then the user will be allowed to allocate
# all free memory with a single process, minus admin_reserve_kbytes.
# Any subsequent attempts to execute a command will result in
# "fork: Cannot allocate memory".
#
# Changing this takes effect whenever an application requests memory.
# ==============================================================

TEST_SUCCESS=true

if [ -f "/proc/sys/vm/user_reserve_kbytes" ]; then
	USER_RESERVE_KBYTES=`/bin/cat /proc/sys/vm/user_reserve_kbytes`

	# check the default valuse
	if [ $USER_RESERVE_KBYTES -le 131072 ]; then
		echo "user_reserve_kbytes = $USER_RESERVE_KBYTES"
	else
		echo "user_reserve_kbytes = $USER_RESERVE_KBYTESL"
		TEST_SUCCESS=false
	fi

	# change the size
	for new_size in 0 10240 131072; do
		echo $new_size > /proc/sys/vm/user_reserve_kbytes	  || TEST_SUCCESS=false
	done
	echo $USER_RESERVE_KBYTES > /proc/sys/vm/user_reserve_kbytes	  || TEST_SUCCESS=false

	# check if test PASS
	if $TEST_SUCCESS; then
		echo "finished running the test. PASS"
		exit 0;
	else
		echo "please check log message. FAIL"
		exit 1;
	fi

else
	echo "user_reserve_kbytes is not exsit, system does not support the feature"
	exit 1;
fi
