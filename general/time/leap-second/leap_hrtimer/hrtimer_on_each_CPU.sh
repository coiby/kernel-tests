#!/bin/bash

COUNT=`/usr/bin/getconf _NPROCESSORS_ONLN`

for i in `seq 0 $((--COUNT))`
do
    taskset -c $i ./hrtimer &
done
