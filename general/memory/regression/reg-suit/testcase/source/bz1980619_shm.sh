#!/bin/sh

MAX=32768;
N=1024;

echo $MAX > /proc/sys/kernel/shmmni;

while [ $N -le $MAX ]; do
	./shm-test $N;
	N=$((N*2));
done 

