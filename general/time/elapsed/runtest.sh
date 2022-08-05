#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/elapsed"

function runtest()
{
    gcc -o elapsed elapsed.c
    for i in {1..10}; do
        ./elapsed >> ./output.log 2>&1
    done
    rstrnt-report-log -l output.log

    if grep "ERROR" ./output.log; then
        rstrnt-report-result $TEST "FAIL" 1
    else
        rstrnt-report-result $TEST "PASS" 0
    fi
}

runtest
exit 0
