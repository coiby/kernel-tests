#!/bin/bash

function sched_setattr()
{
	rlRun "gcc sched_setattr.c -o sched_setattr" || return

	rlRun "./sched_setattr 100000000" 0 "100ms slice"
	rlRun "./sched_setattr 1000000" 0 "1ms slice"
	rlRun "./sched_setattr 200000" 0 "0.2ms slice"

	rlRun "./sched_setattr 20000" 0 "0.02ms slice"
	rlRun "./sched_setattr 500000000" 0 "500ms slice"

	# test the cgroup migration between two cpu groups
	check_cgroup_version
	cgroup_create "eevdf1" cpu
	cgroup_create "eevdf2" cpu
	cgroup_set "eevdf1" cpu cpu.shares=512
	cgroup_set "eevdf2" cpu cpu.shares=1

	rlRun "gcc sched_setattr_loop.c -o sched_setattr_loop"
	rlLogInfo "run sched_setattr_loop in background for 130s"
	./sched_setattr_loop 0 130 &
	local pid=$!

	# wait for 3s for the thread to start
	local limit=3
	while ! ps -C sched_setattr_loop; do
		echo "Waiting for sched_setattr_loop to start"
		sleep 1
		((--limit > 0)) || break
	done

	# check if finally the thread started
	if ps -C sched_setattr_loop; then
		echo "$(date +%H:%m:%S): sched_setattr_loop started"
	else
		rlReport "start test process" FAIL
		return
	fi

	local cg1=$(cgroup_get_path eevdf1 cpu)
	local cg2=$(cgroup_get_path eevdf2 cpu)
	echo "cg1=$cg1 cg2=$cg2"
	# migrating between two cpu groups, for race detection
	for i in $(seq 1 1000); do
		if ((i % 50 == 0)); then
			echo "$(date +%H:%m:%S) loop $i"
		fi
		echo $pid > $cg1/$CGROUP_TASK_FILE
		if ! ps -C sched_setattr_loop > /dev/null; then
			echo "test process sched_setattr_loop quited"
			break
		fi
		sleep 0.1
		echo $pid > $cg2/$CGROUP_TASK_FILE
		if dmesg | grep -i 'call trace'; then
			rlReport dmesg "FAIL"
			ps -p $pid -C sched_setattr_loop && kill $pid
			break
		fi
	done
	rlReport "sched_setattr_cgroup_migration" PASS

	# clean up
	ps -p $pid -C sched_setattr_loop && kill $pid
	rm -f sched_setattr sched_setattr_loop
	cgroup_destroy eevdf1 cpu
	cgroup_destroy eevdf2 cpu
}
