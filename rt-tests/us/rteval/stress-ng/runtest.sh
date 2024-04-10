#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

export RTEVAL_DURATION=${RTEVAL_DURATION:-30s}
export TEST="rt-tests/us/rteval/stress-ng"

function runtest()
{
    log "Package rteval stress-ng loads test:"
    rm -f rteval.log

    oneliner "yum install -y stress-ng"

    # Options for the stressng module:
    #   --stressng-option=OPTION
    #                       stressor specific option
    #   --stressng-arg=ARG  stressor specific arg
    #   --stressng-timeout=T
    #                       timeout after T seconds

    # CPU stressor: branch
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=branch --stressng-arg=0"
    # Cache stressor: cache
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=cache --stressng-arg=0"
    # Interrupt stressor: clock
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=clock --stressng-arg=0"
    # Memory stressor: stack
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=stack --stressng-arg=0"
    # OS stressor: fifo
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=fifo --stressng-arg=0"
    # OS stressor: lockf
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=lockf --stressng-arg=0"
    # OS stressor: mlock
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=mlock --stressng-arg=0"
    # OS stressor: pthread
    oneliner "rteval --duration=$RTEVAL_DURATION --stressng-option=pthread --stressng-arg=0"
}

if rhel_in_range 0 8.2; then
    rstrnt-report-result "Not supported in RHEL-RT < 8.3 -- skipping test case" "SKIP" 0
    exit 0
fi

runtest
exit 0
