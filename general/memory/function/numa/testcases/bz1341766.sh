#!/bin/bash
#yaoma@redhat.com

function delete_tmp {
	rm -rf /tmp/numa_mm_1.log
	rm -rf /tmp/numa_mm_0.log
	rm -rf /tmp/numa_mm_1_leaktest.log
	rm -rf /tmp/numa_mm_0_leaktest.log
	rm -rf ./bz1341766
}

set -x

if [ $(numactl -H | grep available | awk '{print $2}') -lt 2 ]; then
	exit 0
fi

gcc bz1341766.c -o bz1341766 -fopenmp

#echo 3 >/proc/sys/vm/drop_caches
#echo 1 >/proc/sys/vm/compact_memory

numactl -H | grep free > /tmp/numa_mm_1.log
numactl -m 1 ./bz1341766
numactl -H | grep free > /tmp/numa_mm_1_leaktest.log

val_n1_f=$(cat /tmp/numa_mm_1.log | grep "^node 1 free:" | awk -F' ' '{ print $4 }')
val_n1_l=$(cat /tmp/numa_mm_1_leaktest.log | grep "^node 1 free:" | awk -F' ' '{ print $4 }')

total_leak=$(expr $val_n1_f - $val_n1_l)

echo "total mm leak" $total_leak " M"

if [ "$total_leak" -ge "32" ]; then
	echo "mem leak over 32M"
	delete_tmp
	exit 1
fi

#echo 3 >/proc/sys/vm/drop_caches
#echo 1 >/proc/sys/vm/compact_memory

numactl -H | grep free > /tmp/numa_mm_0.log
numactl -m 0 ./bz1341766
numactl -H | grep free > /tmp/numa_mm_0_leaktest.log

val_n0_f=$(cat /tmp/numa_mm_0.log | grep "^node 0 free:" | awk -F' ' '{ print $4 }')
val_n0_l=$(cat /tmp/numa_mm_0_leaktest.log | grep "^node 0 free:" | awk -F' ' '{ print $4 }')

total_leak=$(expr $val_n0_f - $val_n0_l)

echo "total mm leak" $total_leak " M"

if [ "$total_leak" -ge "32" ]; then
	echo "mem leak over 32M"
	delete_tmp
	exit 1
fi

delete_tmp
exit 0


