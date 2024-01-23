#!/bin/bash

function bz1738415()
{
	local binary_name=${1:-${FUNCNAME[0]}}
	if ! type -t rlRun; then
		. /usr/share/beakerlib/beakerlib.sh
	fi
	rlRun "gcc -o $binary_name ./load.c" || return 1
	set -x
	unset CGROUP_VERSION
	check_cgroup_version

	cgroup_create test/test1/test2 cpu
	cgroup_create TEST/test1/test2 cpu

	local file
	if [ "$CGROUP_VERSION" = 1 ]; then
		file=cpu.cfs_quota_us
	else
		file=cpu.max
	fi

	cgroup_set test				cpu $file=40000
	cgroup_set TEST             cpu $file=40000
	cgroup_set TEST/test1       cpu $file=30000
	cgroup_set test/test1       cpu $file=30000
	cgroup_set test/test1/test2 cpu $file=20000
	cgroup_set TEST/test1/test2 cpu $file=20000
	set +x

	rlRun "$CGROUP_EXEC TEST/test1 cpu ./${binary_name} &"
	local pid_p=$!
	[ "$pid_p" = 0 ] && echo "xxxxxxxx no process!" && return 1
	rlRun "./migrate.sh $pid_p &"
	KILL_PIDS+=" $!"
	KILL_NAMES+=" $binary_name"
}

function bz1738415_cleanup()
{
	cgroup_destroy test/test1/test2 cpu
	cgroup_destroy test/test1 cpu
	cgroup_destroy test	cpu

	cgroup_destroy TEST/test1/test2 cpu
	cgroup_destroy TEST/test1 cpu
	cgroup_destroy TEST cpu
}
