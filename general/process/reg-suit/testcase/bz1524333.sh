#!/bin/bash

function bz1524333()
{
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME} -lpthread"
	rlRun "${DIR_BIN}/${FUNCNAME}" 0-255 "no panic then pass"
}
