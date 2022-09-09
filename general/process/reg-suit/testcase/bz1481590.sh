#!/bin/bash

function bz1481590()
{
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}"
}
