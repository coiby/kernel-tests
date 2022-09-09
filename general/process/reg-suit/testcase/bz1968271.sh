#!/bin/bash
function bz1968271()
{
	if rlIsRHEL ">=8"; then
		if rlIsRHEL "<8.1" ; then
			mark_skip $FUNCNAME "fixed in 8.5 4.18.0--318.el8"
			return
		fi
	fi
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -lpthread -o ${DIR_BIN}/${FUNCNAME}"
	timeout 10 ${DIR_BIN}/${FUNCNAME}
}
