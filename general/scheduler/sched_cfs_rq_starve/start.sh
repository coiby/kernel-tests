#!/bin/sh

NUM_CPUS=$(nproc)
((NUM_CPUS > 24)) && NUM_CPUS=24
for i in $(seq 1 $NUM_CPUS) ; do
	./cputest $i &
done
