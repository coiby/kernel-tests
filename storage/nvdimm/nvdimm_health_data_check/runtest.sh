#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	[[ $(arch) == "x86_64" ]] && tok "modprobe acpi_ipmi"
	tok "ndctl list -BHD"
	if [ $? -eq 0 ]; then
		tlog "INFO: nvdimm health data check pass"
	else
		tlog "INFO: nvdimm health data check failed"
	fi
	tnot "ndctl list -BDH | grep -E \"health_state\":\"fatal|critical|non-critical\""
	if [ $? -eq 1 ]; then
		tlog "INFO: health_state:fatal|critical|non-critical found"
	else
		tlog "INFO: no health_state:fatal|critical|non-critical found"
	fi
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
