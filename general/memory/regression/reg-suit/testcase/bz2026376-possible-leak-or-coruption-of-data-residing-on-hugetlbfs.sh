#!/bin/bash
function bz2026376()
{
	local check=_compile
	if rlIsRHEL "<8" && check=_release || ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
		report_result ${FUNCNAME}$check SKIP
		mark_skip "$FUNCNAME"
		return
	elif ! uname -r | grep x86_64; then
		report_result ${FUNCNAME}_skip_arch SKIP
		mark_skip "$FUNCNAME"
		return
	fi

	local old=$(cat /proc/sys/vm/nr_hugepages)

	sysctl vm.nr_hugepages=1024
	rlRun "./${FUNCNAME}" 0

	echo $old > /proc/sys/vm/nr_hugepages
}
