#!/bin/bash

function bzsigaction()
{
	local data_addr=$(awk '/sysctl_sched_cfs_bandwidth_slice/ {print $1}' /proc/kallsyms)
	uname -m | grep x86_64 || return
	if rlIsRHEL "<8"; then
		local def="-D RHEL7"
	fi
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME} $def"
	rlLog "sysctl_sched_cfs_bandwidth_slice: $data_addr"
	dmesg -C
	rlRun "$DIR_BIN/${FUNCNAME} $data_addr" 139
	if test -f /proc/sys/debug/exception-trace; then
		rlRun "echo 1 > /proc/sys/debug/exception-trace"
		rlRun "dmesg | grep Code: [0-9a-f]+" 1-255
	fi
}
