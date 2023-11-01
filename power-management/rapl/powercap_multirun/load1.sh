#!/bin/bash

if [ -z "$1" ]; then
        sleeptime=1
else
        sleeptime="$1"
fi

#do some load
dd if=/dev/zero >/dev/null &

loadpid="$!"

sleep "$sleeptime"
# wait a bit longer, than length of test
sleep 10

#kill the load
kill "$loadpid"

