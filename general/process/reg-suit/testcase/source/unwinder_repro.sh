#!/bin/bash

COUNT=$(nproc)

# Lots of processes exiting.
for n in $(seq $COUNT)
do
    echo "exit $n"
    while : ; do /bin/true > /dev/null 2>&1 < /dev/null ; done &
done

# Lots of /proc stack accesses.
for n in $(seq $COUNT)
do
    echo "proc $n"
    while : ; do cat /proc/*/task/*/stack > /dev/null 2>&1 < /dev/null ; done &
done

