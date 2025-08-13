#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

source ../../../cki_lib/libcki.sh

function runtest
{
	if [ -f '/sys/kernel/debug/kmemleak' ]; then
		rlRun "echo scan > /sys/kernel/debug/kmemleak"
		rlRun "sleep 120"
		dmesg | grep "kmemleak.*new suspected memory leaks"
		if [ $? -eq 0 ]; then
			rlRun "cat /sys/kernel/debug/kmemleak"
			rstrnt-report-result "${RSTRNT_TASKNAME}" FAIL
		else
			rstrnt-report-result "${RSTRNT_TASKNAME}" PASS
		fi
	else
		rstrnt-report-result "${RSTRNT_TASKNAME}" SKIP
	fi
}

cki_main
