#!/bin/bash
function bz1918288()
{
	rlIsRHEL "<8" && c_flag="-std=gnu99"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -lpthread $c_flag -o ${DIR_BIN}/${FUNCNAME}" || return
	timeout 5 ${DIR_BIN}/${FUNCNAME}
	rlRun "dmesg | grep  rtc_timer_do_work" 1-255
}
