#!/bin/bash
function bz1993665()
{
	if rlIsRHEL "<8.6"; then
		report_result ${FUNCNAME} SKIP
		((DEBUG_MODE)) || return
	fi
	yum -y install strace golang &>/dev/null
	for x in $(seq 1 50) ; do go build $DIR_SOURCE/${FUNCNAME}_xx.go && timeout -s 9 6 strace -f ./${FUNCNAME}_xx 2>/dev/null; done | uniq -c | tee ${FUNCNAME}.log
	rlRun "grep 50 ${FUNCNAME}.log" 0 "50 hello should be printed"

	echo "cat ${FUNCNAME}.log"
	cat "${FUNCNAME}.log"
	return 0
}
