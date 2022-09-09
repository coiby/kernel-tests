#!/bin/bash

function bz1579402()
{
	if ! rlIsRHEL ">=7.6"; then
		rlPhaseStartTest "$FUNCNAME skip"
		rlLog "From rhel7.6 this is supported"
		rlPhaseEnd
		return
	fi
	local shmid="-1"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}_create.c -o ./${FUNCNAME}_c"
	rlRun "gcc $DIR_SOURCE/${FUNCNAME}_attach.c -o /home/test/${FUNCNAME}_a"
	rlRun "chown -R test:test /home/test/${FUNCNAME}_a"
	rlRun "shmid=$(./${FUNCNAME}_c)"
	if [ -z "$shmid" ]; then
		rlFail "create shm failed"
		return 1
	fi
	rlRun "su test -c \"/home/test/${FUNCNAME}_a $shmid\""
	rm -f /home/test/${FUNCNAME}_a
}
