#!/bin/bash
function bz1511040()
{
	local pid
	local pid_check
	local nr_cpus=$(nproc)
	local thread_break_time=30
	local thread_break_centisec=3000
	(( $(free -g | awk '/Mem/ {print $4}') < 2 || nr_cpus ==1 )) && echo "Skipped bz1511040 as nr_cpus=1 or free_mem<2G" && return

	rpm -q numactl-devel || yum -y install numactl-devel &>/dev/null

	rpm -q numactl-devel || { report_result ${FUNCNAME} SKIP; return 0; }

	rlRun "gcc $DIR_SOURCE/pig.c -std=gnu99 -lpthread -lm -lnuma -o pig" || return 1
	rlRun "./pig -p 1 -l splice -t $nr_cpus -s 120 -b $thread_break_centisec -v &"
	pid=$!
	sleep 2 # wait for threads start
	rlRun "ps -TC pig -o tid,pid,psr,comm,pcpu,etimes"

	# wait for threads exit, and main thread run for 5 seconds
	sleep $((thread_break_time + 5))

	rlRun "ps -TC pig -o tid,pid,psr,comm,pcpu,etimes" 0 "single thread mode (other threads ended)"
	sh $DIR_SOURCE/bz1511040_check.sh $pid > ${FUNCNAME}.log &
	pid_check=$!

	rlRun "ps -Tp $pid_check -o tid,pid,psr,comm,pcpu,etimes,args"
	pstree -nalp $(ps -C restraintd --no-headers -o pid | awk '{gsub(" ","");print}')

	# wait for the main thread stablely run short period to sample
	sleep 12

	ps -p $pid_check -o args | grep check && rlRun "kill $pid_check"

	ps -p $pid -o args | grep pig && kill -9 $pid
	echo "marking bz1511040_done"
	touch /mnt/bz1511040_done

	rlFileSubmit ${FUNCNAME}.log

	rlAssertNotExists  FAILED
	test -f FAILED && rm -f FAILED

}
