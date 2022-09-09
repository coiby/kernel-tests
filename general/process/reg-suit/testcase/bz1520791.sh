#!/bin/bash

function bz1520791()
{
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}"
	rlRun "ls linux-acct" -l 0-255
}
