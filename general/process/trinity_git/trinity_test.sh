#!/bin/bash

TRINITY_WRKDIR=/mnt/testarea/trinity_scratch
rm -rf $TRINITY_WRKDIR &> /dev/null
mkdir $TRINITY_WRKDIR
pushd $TRINITY_WRKDIR
proc_num=$(cat /proc/cpuinfo | grep ^processor | wc -l)
if [ -z "$proc_num" ]; then
	proc_num=1
fi

child_num=$((proc_num*2))
if [ "$child_num" -gt 16 ]; then
	child_num=16
fi

MALLOC_CHECK_=2 trinity --children $child_num --syslog -q -T DIE $SKIP_TESTS
popd
