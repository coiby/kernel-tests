#!/bin/bash

numastat || exit 1
numastat -c || exit 1
numastat -m || exit 1
numastat -n || exit 1
numademo -t 32M memset memcpy forward backward stream random2 ptrchase || exit 1
exit 0
