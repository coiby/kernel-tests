#!/bin/bash
function bz1755143()
{
	local nrcpu=$(nproc --all)
	for i in $(seq 1 $nrcpu);
	do
		yes > /dev/null &
	done
	pkill yes
	pkill yes
	timeout 3 perf top -g > /dev/null
}
