#!/bin/bash
set -x

if [ $(uname -m) == "x86_64" ]; then
    if [ $(numactl -H | grep available | awk '{print $2}') -ge 2 ]; then
        gcc bz802379.c -lnuma -o bz802379
        ./bz802379 | tee -a bz802379.log > /dev/null &
        pid=$!
        sleep 30 && pkill -0 bz802379 && kill -9 $pid
        if grep 'Hit the bug' bz802379.log; then
            exit 1
        else
            exit 0
        fi
    fi
fi
