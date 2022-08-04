#!/bin/bash
set -x

echo 3 > /proc/sys/vm/drop_caches

if [ $(numactl -H | grep available | awk '{print $2}') -ge 2 ]; then
    gcc -lpthread -o bz1277241 bz1277241.c
    if ! numactl -H | grep 'node 1 size'; then
        exit
    fi
    numactl -H
    node1size=$(numactl -H | grep 'node 1 size' | awk '{print $4}')
    thread=$(grep -c processor /proc/cpuinfo)
    if [ $thread -gt 10 ]; then
        thread=10
    fi
    len=$(echo "$node1size / $thread" | bc)
    if [ $len -gt 1024 ]; then
        len=1024
    fi
    ./bz1277241 $thread $len 0 &
    pid=$!
    sleep 280
    actual=$(numastat -p $pid -c | awk 'END{print $3}')
    theory=$(echo "$thread * $len" | bc)
    reference=$(echo "$theory / 1.2" | bc)
    if [ $actual -lt $reference ]; then
        echo "actual=$actual theory=$theory"
        numastat -p $pid -c
        exit 1
    fi
    pkill -9 $pid
fi
exit 0
