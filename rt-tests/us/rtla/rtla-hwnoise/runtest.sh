#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

export TEST="rt-tests/us/rtla/rtla-hwnoise"

function runtest()
{
    # rtla hwnoise supports from 8.9 and 9.2
    if rhel_in_range 0 8.8 || rhel_in_range 9.0 9.1; then
        echo "rtla hwnoise is only supported for RHEL >= 8.9 and >= 9.2" || tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" 0
        exit 0
    fi

    oneliner "yum install -y rtla"

    # verify help page
    oneliner "rtla hwnoise --help"
    # detect noise higher than one microsecond
    oneliner "rtla hwnoise -c 0 -T 1 -d 5s -q"

    #set the automatic trace mode
    phase_start_test "rtla hwnoise -a 5 -d 30s"
    run "rtla hwnoise -a 5 -d 30s" "0 2"
    phase_end

    # set scheduling param to the osnoise tracer threads
    oneliner "rtla hwnoise -P F:1 -c 0 -r 900000 -d 1M -q"

    # stop the trace if a single sample is higher than 1 us
    phase_start_test "rtla hwnoise -s 1 -T 1 -t -d 30s"
    run "rtla hwnoise -s 1 -T 1 -t -d 30s" "0 2"
    phase_end

    # enable a trace event trigger
    # shellcheck disable=SC2140
    oneliner "rtla hwnoise -t -e osnoise:irq_noise --trigger="hist:key=desc,duration:sort=desc,duration:vals=hitcount" -d 1m"
}

runtest
exit 0
