#!/bin/bash

interval=1

function loop
{
	local i
	for ((i=0; i < 10000; i++))
	do
		echo 1 > /sys/kernel/slab/kmalloc-512/shrink
	done
}

function bz1921056()
{
	rlIsRHEL 8 || rlLogInfo "Test case is for RHEL-8" && return

	rlRun "insmod ${DIR_MODULE}/${FUNCNAME}.ko"
	c=0
	while [ $c -le 60 ]
	do
		printf "count: %d\n" $c
		echo $interval > /proc/kmalloc512er
		loop
		sleep 1
		c=$((c+1))
	done
	rlRun "rmmod ${FUNCNAME}"
}
