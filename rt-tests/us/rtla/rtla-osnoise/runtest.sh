#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rtla/rtla-osnoise"

function runtest()
{
    # rtla supports from 8.8 and 9.2
    if rhel_in_range 0 8.7 || rhel_in_range 9.0 9.1; then
        echo "rtla osnoise is only supported for RHEL >= 8.8 and >= 9.2" || tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" 0
        exit 0
    fi

    oneliner "yum install -y rtla"

    # verify help page
    oneliner "rtla osnoise --help"

    # rtla-osnoise top test: verify the --priority/-P param
    oneliner "rtla osnoise top -P F:1 -c 0 -r 900000 -d 1M -q"
    # rtla-osnoise top test: verify the --stop/-s param
    oneliner "rtla osnoise top -s 30 -T 1 -t"
    # rtla-osnoise hist test: verify the  --trace param
    oneliner "rtla osnoise hist -s 30 -T 1 -t"
    # rtla-osnoise hist test: verify the --entries/-E param
    oneliner "rtla osnoise hist -P F:1 -c 0 -r 900000 -d 1M -b 10 -E 25"
}

if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    rt_env_setup
    enable_tuned_realtime
fi

runtest
exit 0
