#!/bin/bash
function bz1808931()
{
	if rlIsRHEL "8.2" && kver_ge 4.18.0-193.45.1.el8_2.dt1; then
		true
	elif rlIsRHEL "<8.3"; then
		return
	fi
	rlLogInfo "mq_notify()"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -lrt -o ${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}" 0
}
