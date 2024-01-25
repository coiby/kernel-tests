#!/bin/bash
#
# Description:
#   When the loop module is loaded, it creates 8 loop devices
#   /dev/loop[0-7]. These devices have no request routine. Thus,
#   when they are used without being assigned, a crash happens.

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh		|| exit 1
. /usr/share/beakerlib/beakerlib.sh			|| exit 1

cnt=1
for (( i=0; i<=7; i++ ))
do
	if [ ! -e /dev/loop$i ]; then
		/bin/mknod /dev/loop$i b 7 $i
		if [ $? -ne 0 ]; then
			rlLogWarning "/bin/mknod failed."
			exit 2
		fi
	else
		/sbin/losetup -a | /bin/grep /dev/loop$i >/dev/null
		if [ $? -eq 0 ]; then
			continue
		fi
	fi
	eval "loop_dev$cnt=/dev/loop$i"
	if [ $cnt -eq 2 ]; then
		break
	fi
	cnt=$(($cnt+1))
done

# shellcheck disable=SC2154
/sbin/dmsetup create test_snap --table \
	"0 1 snapshot $loop_dev1 $loop_dev2 P 32" 2>&1 | \
	/bin/grep "Input\/output error"
if [ $? -eq 0 ]; then
	echo "Bug is not reproduced."
	exit 0
else
	/sbin/dmsetup create test_snap --table \
		"0 1 snapshot $loop_dev1 $loop_dev2 P 32"
	rlLogWarning "/sbin/dmsetup failed."
	exit 2
fi
