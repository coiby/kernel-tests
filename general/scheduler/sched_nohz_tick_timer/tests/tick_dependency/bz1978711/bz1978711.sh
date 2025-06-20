#!/bin/bash

function bz1978711()
{
	git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
	pushd rt-tests
	git checkout stable/v1.0
	if grep 'int sched_setattr' /usr/include/bits/sched.h; then
		echo "sched_attr" is defined in glic-headers.
		echo "Undefine it in the source in case of redefinition errorr."
		patch -p1 < ../undefine_sched_attr.patch
	fi
	make -j4
	# this is defined in runtest.sh
	# shellcheck disable=SC2154
	local cpu=$first_isolated
	set -x
	./cyclictest -a $cpu --policy=fifo --priority=10 -t 1 &
	set +x

	sleep 2
	rlRun -l "ps -LC cyclictest -o pid,tid,psr,pcpu,etimes,args"
	[ $? -ne 0 ] && rstrnt-report-result "cyclictest_compile" FAIL && return

	echo > /sys/kernel/debug/tracing/trace

	rlRun -l "cat /sys/kernel/debug/tracing/{set_event,tracing_on,current_tracer,set_ftrace_filter,tracing_cpumask}"
	# shellcheck disable=SC2154
	rlRun "grep $tick_symb /sys/kernel/debug/tracing/trace" 1-255

	while ps -C cyclictest; do
		pkill cyclictest
	done

	popd
}

function bz1978711_cleanup()
{
	true
}
