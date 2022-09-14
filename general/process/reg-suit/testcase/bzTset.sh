#!/bin/bash
function bzTset()
{
	local iter=0
	local arch=$(uname -m)
	local skip=0
	[ ! "$arch" = x86_64 ] && [ ! "$arch" = i686 ] && rlLogInfo "Skip ldt(bzTldt) testing" && skip=1
	# ldt testing, just for coverage, to make it a function, needs to be tuned
	if ((skip == 0)); then
		rlRun "gcc $DIR_SOURCE/bzTldt.c -o ${DIR_BIN}/${FUNCNAME}$((++iter)) -m32"
		rlRun "${DIR_BIN}/${FUNCNAME}${iter}"
	fi
	skip=0
}
