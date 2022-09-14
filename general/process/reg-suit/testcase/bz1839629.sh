#!/bin/bash
function bz1839629()
{
	local old_hard=$(cat /proc/sys/fs/pipe-user-pages-hard)
	local old_soft=$(cat /proc/sys/fs/pipe-user-pages-soft)
	local old_files=$(ulimit -n)

	rlIsRHEL ">=7.9" || rlIsFedora ">=30" || { ((FORCE)) || return; }

	rlRun "echo 1000 > /proc/sys/fs/pipe-user-pages-hard"
	rlRun "echo 1 > /proc/sys/fs/pipe-user-pages-soft"

	rlRun "gcc $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME}" || return 1
	ulimit -n 10000
	rlRun "ulimit -n 10000"
	rlRun "${DIR_BIN}/${FUNCNAME} 1000"

	rlRun "echo $old_hard > /proc/sys/fs/pipe-user-pages-hard"
	rlRun "echo $old_soft > /proc/sys/fs/pipe-user-pages-soft"
	rlRun "ulimit -n $old_files"
}
