#!/bin/bash

function bz1597991()
{
	if rlIsRHEL "<7.7"; then
		rlReport "${FUNCNAME}-skip" PASS
	fi
	! test -f /proc/sys/user/max_user_namespaces && return
	local old=$(cat /proc/sys/user/max_user_namespaces)
	local new=100
	rlRun "sysctl user.max_user_namespaces=$new"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -lpthread -o ${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}"
	rlRun "echo $old > /proc/sys/user/max_user_namespaces"
	rlRun "pkill -f bz1597991" 0-255
}
