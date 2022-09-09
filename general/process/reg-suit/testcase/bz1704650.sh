#!/bin/bash

function bz1704650()
{
	if uname -r | grep mr && ! uname -r | grep x86_64; then
		report_result "${FUNCNAME}_module_compile" SKIP
		return
	fi
	local dir_module=$DIR_MODULE/spurious_waker
	test -f $dir_module/sigsuspend && $dir_module/sigsuspend &
	local spid=$!
	rlRun "insmod $dir_module/wakeup.ko pid=$spid"
	sleep 8

	rmmod wakeup
	kill $spid
}
