#!/bin/bash
function bz2089715()
{
	local c_flag
	# rlIsRHEL "<8" && c_flag="-std=gnu99"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME[0]}.c $c_flag -o ${DIR_BIN}/${FUNCNAME[0]}" || return
	rlRun ${DIR_BIN}/${FUNCNAME[0]}
}
