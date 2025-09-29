#!/bin/bash

DURATION="${DURATION:-"5m"}"
STRESS_THREADS="${STRESS_THREADS:-"2"}"

# Source rt common functions
. ../../../include/lib.sh || exit 1
function runtest()
{
    if rhel_in_range 0 9.2; then
        report_result "rv is only supported for RHEL >= 9.3" "SKIP" 0
        exit 0
    fi


    oneliner "dnf install -y rv stress-ng"

    phase_start_test wwnr

    # Start rv and stress-ng
    run "rv mon wwnr -r printk -t >rv.log" &
    rv_pid=$!
    sleep 1s
    run 'rv list | grep "wwnr.*\[ON]"'
    run -l "rv list"
    run "stress-ng --timer $STRESS_THREADS" &
    stress_pid=$!

    # Wait for a while to collect data
    sleep "$DURATION"

    # Clean up rv and stressng processes
    run "kill -INT $rv_pid"
    run "kill -INT $stress_pid"

    # Check logfile
    events=$(grep -cE "\[[0-9]+] event" rv.log)
    errors=$(grep -cE "\[[0-9]+] error" rv.log)

    log "$events events found"
    log "$errors errors found"

    if [[ $events = "0" ]] ; then
        log_fail "Found no events"
        PHASE_STATUS=FAIL
    fi

    if [[ $errors = "0" ]] ; then
        log_fail "Found no errors while testing error generation"
        PHASE_STATUS=FAIL
    fi

    rstrnt-report-log -l "rv.log"

    phase_end
}

runtest
