#!/bin/bash
function bz1015985()
{
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}" 1-255 "This is for checking warning in dmesg"
}
