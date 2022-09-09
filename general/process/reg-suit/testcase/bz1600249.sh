#!/bin/bash

function bz1600249()
{
	uname -m | grep ppc64le || return
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME} -lpthread"
	rlRun "taskset -c 1 ${DIR_BIN}/${FUNCNAME} | tee sched_getcpu.log"
	local cpu_double=$(awk -F= '{ORS="";gsub(" ","");print $2}' sched_getcpu.log)
	rlAssertNotEquals "the expected cpu affinity should show 11, (1 and 1) or (1100001?), at least not 0" $cpu_double "00"
}
