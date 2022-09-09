#!/bin/bash
function bzdeadline()
{
	local dpid
	local pcpu

	rlIsRHEL "<8" && return

	rlRun "gcc -lpthread $DIR_SOURCE/${FUNCNAME}.c -o ${DIR_BIN}/${FUNCNAME}" || return
	${DIR_BIN}/${FUNCNAME} &
	dpid=$!
	rlRun -l "ps -C bzdeadline -o pid,pcpu,policy,comm"
	sleep 5
	rlRun -l "ps -C bzdeadline -o pid,pcpu,policy,comm"

	ps -AL | grep bzdeadline || return

	pcpu=$(ps -C bzdeadline --no-headers -o pcpu)

	# cpu usage should around (33%)
	[ "$(echo $pcpu \> 40 | bc)" = 1 ]
	local cmp=$?
	rlAssertNotEquals "constraint bd should be around <43" 0 $cmp

	[ "$(echo $pcpu < 23 | bc)" = 1 ]
	local cmp=$?
	rlAssertNotEquals "constraint bd should be around >23" 0 $cmp

	rlRun "ps -C bzdeadline | grep deadline && kill -9 $dpid" 0-255

}
