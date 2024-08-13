#!/bin/bash
function bz1797429()
{
	which stress-ng &>/dev/null || { pushd ../../../include/scripts/; sh stress.sh; popd; }
	which stress-ng &>/dev/null || { report_result "stress-ng-install" SKIP; return; }
	rpm -q perf || yum -y install perf &>/dev/null
	perf trace -e clone --duration 100 stress-ng --fork 1 -t 6 &
	# Fix me, this should be in serial
	timeout 5 agetty /dev/ttyS0 115200
	echo t > /proc/sysrq-trigger
}
