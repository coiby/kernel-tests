#!/bin/bash
function bz1609717()
{
	rlRun "$DIR_SOURCE/unwinder_repro.sh"
	rlRun -l "ps -AL -o args,pid | grep unwinder" 0-255
	for p in $(ps -AL -o pid,args | awk  '/unwind/ {print $1}'); do
		kill -9 $p
	done
	rlRun -l "ps -AL -o args,pid | grep unwinder" 0-255
}
