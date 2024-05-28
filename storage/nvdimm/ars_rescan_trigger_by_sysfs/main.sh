#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	tok "find /sys -name scrub"
	SCRUB_PATH=$(find /sys -name scrub | grep ACPI | tail -1)
	tok "time ndctl wait-scrub"

	trun ndctl start-scrub
	if [ $? -eq 0 ]; then
		tlog "INFO: will trigger acpi_nfit_ars_rescan: ${SCRUB_PATH}"
		tok "time ndctl wait-scrub"
		tok "echo 1 > ${SCRUB_PATH}"
		tok "echo ${SCRUB_PATH}"
		num=$(cat "$SCRUB_PATH")
	else
		tlog "INFO: scrub operation not supported"
	fi
	tlog "INFO: acpi_desc->scrub_count value is: $num"
}

tlog "running $0"
trun "uname -a"
runtest

tend
