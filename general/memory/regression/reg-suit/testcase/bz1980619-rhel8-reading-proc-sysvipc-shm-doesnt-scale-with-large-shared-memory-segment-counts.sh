#!/bin/bash
function bz1980619()
{
	rlRun "gcc -o shm-test $DIR_SOURCE/${FUNCNAME}.c"
	rlRun "${DIR_SOURCE}/${FUNCNAME}_shm.sh | tee ${FUNCNAME}.log"
	local max_time=$(awk 'BEGIN{a=0} {if (a<=$1) a=$1}END{print a}' ${FUNCNAME}.log)
	if ((max_time > 500)); then
		if rlIsRHEL ">=8.6"; then
			echo "FAIL"
			report_result "$FUNCNAME" FAIL
		else
			echo "WARN: this failed, but not sure this is expected."
			# Is this fixed in zstream? not sure so WARN
			report_result "$FUNCNAME" WARN
		fi
	fi
}
