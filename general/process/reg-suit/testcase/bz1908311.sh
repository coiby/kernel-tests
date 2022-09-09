#!/bin/bash
function bz1908311()
{
	rlIsRHEL "<8" && c_flag="-std=gnu99"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -lpthread $c_flag -o ${FUNCNAME}" || return
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}_signal.c -lpthread $c_flag -o signal" || return

	local max_process=$(ulimit -u)
	local max_thread=$(sysctl kernel.threads-max | awk '{print $3}')

	timeout 5 ./${FUNCNAME}
	local ret=$?
	rlAssertNotEquals "not return 1" $ret 1
}
