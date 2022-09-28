#!/bin/sh

. ./lib_stress.sh

export CURRENT=$$
export STRESS_FACTOR=2

if [ "$1" = kbuild ]; then
	load_kbuild 1
elif [ "$1" = "stress-ng" ]; then
	load_stress ${2:-6000}
elif [ "$1" = "trace" ]; then
	load_trace ${2:-6000}
else
	load_kbuild 1
fi


