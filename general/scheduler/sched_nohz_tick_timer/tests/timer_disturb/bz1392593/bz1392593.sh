#!/bin/bash

function bz1392593()
{
	rlLogInfo "Start stress-ng cpu stressor stress-ng -c 1 -t 602 &"
	stress-ng -c 1 -t 602 &

	local ppid=$!
	set -x

	sleep 2
	local stress=$(ps -C stress-ng,stress-ng-cpu --no-headers -o pid,ppid | awk -v ppid=$ppid '$2 == ppid {print $1}')
	set +x

	rlRun "taskset -pc 1 $stress"
	rlRun "grep nohz_full /proc/cmdline"
	rlRun "grep isolcpus /proc/cmdline"
	rlRun "sleep 60"
	# this is defined in runtest.sh
	# shellcheck disable=SC2154
	rlRun "grep timer $tracing_dir/trace | grep -v mce" 0-255 "Only mce timer an be there!"
	pkill stress-ng
	while ps -C stress-ng; do
		pkill stress-ng
	done
	return 0
}

function bz1392593_cleanup()
{
	true
}
