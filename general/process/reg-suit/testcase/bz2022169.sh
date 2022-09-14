#!/bin/bash
function bz2022169()
{
	rlIsRHEL "<9" && return
	local old=$(cat /proc/sys/kernel/sched_child_runs_first)
	echo 1 > /proc/sys/kernel/sched_child_runs_first
	echo "Child  run first to eliminathe the race condition that parent dies before child starts to run"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME}"
	rlRun "${DIR_BIN}/${FUNCNAME}" 0 "sleep function should be in it"
	echo $old > /proc/sys/kernel/sched_child_runs_first
}
