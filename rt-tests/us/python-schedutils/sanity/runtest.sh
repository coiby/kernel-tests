#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

export nrcpus rhel_x

function runtest()
{
    log "Package python-schedutils sanity test"
    if [ $rhel_x -ge 9 ]; then
        rstrnt-report-result "python3-schedutils removed from rhel-9" "SKIP" 5
        exit 0
    fi

    if [ $rhel_x -lt 8 ]; then
        oneliner "yum install -y python-schedutils"
    else
        oneliner "yum install -y python3-schedutils"
    fi

    log "INFO: Running 'sleep 1d' in background"
    sleep 1d &
    sleep 1
    declare sleep_pid=$(pgrep -f 'sleep 1d')

    # pchrt: view sched policy
    oneliner "timeout 1m pchrt -p $sleep_pid"

    # pchrt: change policy
    oneliner "timeout 1m pchrt --fifo -p 1 $sleep_pid"
    oneliner "timeout 1m pchrt -p $sleep_pid | grep SCHED_FIFO"

    # kill current 'sleep 1d' so we can spawn a new one for the following test
    kill -9 $sleep_pid ; wait $sleep_pid 2>/dev/null

    if [ $nrcpus -gt 2 ]; then
        # ptaskset: start 'sleep 1d' on CPU 1 & 2
        oneliner "ptaskset -c 1,2 sleep 1d &"
        sleep 1
        sleep_pid=$(pgrep -f 'sleep 1d')

        # ptaskset: verify affinity mask
        oneliner "ptaskset -c -p $sleep_pid"
        oneliner "ptaskset -c -p $sleep_pid | grep '1,2'"

        # kill final 'sleep 1d' prog
        kill -9 $sleep_pid ; wait $sleep_pid 2>/dev/null
    else
        log "Only 2 CPU - skipping 'ptaskset -c 1,2 sleep 1d &' test"
    fi
}

runtest
exit 0
