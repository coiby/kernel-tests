#!/bin/bash
#
# Description 
#   This case measure the time cosumption of test_memcmp.c process on
#   RHEL* system with Huge Zero Page on/off, it make judge the HZP
#   function well or not from the results comparison.
#
# Author: Li Wang <liwang@redhat.com>
# Reference: http://lwn.net/Articles/525301/

DROP_CACHES=`cat /proc/sys/vm/drop_caches`
MEM_TOTAL=`grep MemTotal: /proc/meminfo |awk '{print $2}'`
TIME_ELAPSE0=-1
TIME_ELAPSE1=-1
HZP=-1

# Value Config
echo "MEM_TOTAL= $MEM_TOTAL"
if [ $MEM_TOTAL -gt 8388608 ]; then 
{	MEM=8
	NUM=9
} elif [ $MEM_TOTAL -gt 4194304 ]; then
{
	MEM=4
	NUM=5
} elif [ $MEM_TOTAL -gt 2097152 ]; then
{
	MEM=2
	NUM=3
} else {
	echo "Sorry, the system RAM is too low to test."
	exit 1
}
fi
echo "MEM= $MEM, NUM= $NUM"

if [ -f "/sys/kernel/mm/transparent_hugepage/use_zero_page" ]; then
	# Testing Setup
	HZP=`cat /sys/kernel/mm/transparent_hugepage/use_zero_page`
	echo always >/sys/kernel/mm/transparent_hugepage/enabled
	echo 3 >/proc/sys/vm/drop_caches

	# Testing Phase
	# - testing with use_zero_page disable
	echo 0 >/sys/kernel/mm/transparent_hugepage/use_zero_page
	(time -p taskset -c 0 ./test_memcmp $MEM) 2> memcmp0.log
	TIME_ELAPSE0=`grep real memcmp0.log|awk '{print $2}'`	
	echo "TIME_ELAPSE0= $TIME_ELAPSE0"
	# - testing with use_zero_page enable
	echo 1 >/sys/kernel/mm/transparent_hugepage/use_zero_page
	(time -p taskset -c 0 ./test_memcmp $MEM) 2> memcmp1.log
	TIME_ELAPSE1=`grep real memcmp1.log|awk '{print $2}'`	
	echo "TIME_ELAPSE1= $TIME_ELAPSE1"

	# Testing Clenup
	echo $HZP >/sys/kernel/mm/transparent_hugepage/use_zero_page
	echo $DROP_CACHES >/proc/sys/vm/drop_caches

	# Testing result - compare the time cosumption with HZP on/off
	a=`echo "$TIME_ELAPSE0 > $NUM*$TIME_ELAPSE1" |bc`
	if [ $a -eq 1 ]; then
		echo "Huge Zero Page works well, Test Pass."
		exit 0
	else
		echo "Huge Zero Page works bad, Test Fail."
		exit 1
	fi
else
	echo "Huge Zero Page is not config, Test Fail."
	exit 1
fi
