#!/bin/bash
function bz1915177()
{
	uname -r | grep -q x86 || return
	rlIsRHEL "<8" && c_flag="-std=gnu99"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -lpthread $c_flag -o ${DIR_BIN}/${FUNCNAME}" || return
	timeout 5 ${DIR_BIN}/${FUNCNAME}
	rlRun "dmesg | grep console_unlock" 1-255
}
