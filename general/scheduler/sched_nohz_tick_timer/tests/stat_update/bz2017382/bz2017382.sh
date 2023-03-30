#!/bin/bash

function bz2017382()
{
	local pid
	local ret

	rlIsRHEL ">=8.7" || rlIsRHEL ">=8.4"
	if [ ! $? = 0 ]; then
		report_result "stat_update-$FUNCNAME" SKIP
		return
	fi

	while :; do a=1; done &
	pid=$!

	echo isolated_cpus=$isolated_cpus,mask=$mask

	cat /proc/cmdline

	local start_user_time=$(awk '/cpu'$first_isolated' / {print $2}' /proc/stat)

	taskset -pc $first_isolated $pid &
	sleep 3

	local end_user_time=$(awk '/cpu'$first_isolated' / {print $2}' /proc/stat)
	rpm -q bc || yum -y install bc

	[ "$(echo $end_user_time \> $start_user_time | bc)" = 1 ]
	ret=$?

	rlAssert0 "user time should grow in the past 3 seconds for isolcated cpu" $ret
	ps -p $pid -o pid,pcpu,args

	kill $pid
}

function bz2017382_cleanup()
{
	true
}
