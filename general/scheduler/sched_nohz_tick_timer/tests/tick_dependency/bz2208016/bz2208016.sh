#!/bin/bash

function bz2208016()
{

	cat > hogger.sh << "EOF"
while :; do
	:
done
EOF
	chmod +x hogger.sh
	echo "kernel command line for nohz_full:"
	cat /proc/cmdline

	local mask=$(get_cpu_mask $last_isolated)
	rlRun "echo $mask > $tracing_dir/tracing_cpumask"
	rlRun "echo tick_sched_handle >> $tracing_dir/set_ftrace_filter"
	rlRun "echo function > $tracing_dir/current_tracer"

	# clean the buffer
	true > /sys/kernel/debug/tracing/trace

	echo "using nohz_full cpu $last_isolated for running the cpu hogger, with cpu cgroup $FUNCNAME 0.5 bandwidth"

	check_cgroup_version
	cgroup_create bz2208016 cpu
	# if cgroup v2, cgroup_set() will map to cpu.max with "50000 100000"
	cgroup_set bz2208016 cpu cpu.cfs_quota_us=50000

	timeout 60 $CGROUP_EXEC bz2208016 cpu taskset -c $last_isolated sh hogger.sh &
	local pid=$!

	local i
	local pass=0
	for i in $(seq 1 10); do
		rlRun "grep tick_sched_handle $tracing_dir/trace &>/dev/null" 0-255 && pass=1
		sleep 2
	done
	head -n 20 $tracing_dir/trace

	rlAssertEquals "pass=1" "$pass" 1

	echo "Killing hogger $pid"
	# shellcheck disable=SC2034
	for  i in $(seq 1 5); do
		ps -p $pid -o args | grep hogger.sh && kill $pid && echo "$pid is killed!"
		ps -p $pid -o args | grep hogger.sh || break
	done
	cgroup_destroy bz2208016 cpu
}

function bz2208016_cleanup()
{
	true
}
