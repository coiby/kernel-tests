#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

################################################################################
# I confimed that without stalld running and having the stress-ng timeout set to
# $MAX_RUNTIME will result in the echo taking $MAX_RUNTIME seconds to complete.
#
# With stalld running the echo should complete in less than $MAX_RUNTIME. This
# tells us that the task is indeed being boosted. stalld will also print the PID
# of the process being boosted, giving additional confirmation.
################################################################################

# Enable TMT testing for RHIVOS
. ../../../../automotive/include/rhivos.sh || exit 1
: "${OUTPUTFILE:=runtest.log}"

# Source rt common functions
. ../../../include/runtest.sh || exit 1

# Vars
export TEST="rt-tests/us/stalld/sanity"
STALLD_PID=""
MAX_RUNTIME=120  # seconds


runtime_lt_threshold() { (( runtime < MAX_RUNTIME )) && return 0 || return 1 ; }

# use the last cpu if no isolation is applied, otherwise use the first isolated cpu
get_test_cpu()
{
    local cpu_isolated test_cpu
    cpu_isolated="$(cat /sys/devices/system/cpu/isolated)"
    if [[ -z $cpu_isolated ]]; then
        test_cpu=$(( $nrcpus - 1 ))
    else
        cpu_isolated="$(convert_number_range $cpu_isolated)"
        test_cpu="$(echo $cpu_isolated | cut -d, -f1)"
    fi
    echo $test_cpu
}

test_setup()
{
    # various skip conditions
    if (( nrcpus < 2 )); then
        report_result "needs 2+ cpus for the test" SKIP 1
        exit 0
    fi

    if ! kernel_automotive && rhel_in_range 0 8.3; then
        report_result "stalld not supported" SKIP 2
        exit 0
    fi

    phase_start_setup

    # install and start stalld
    run "yum install -y stalld stress-ng"
    run -l "systemctl status stalld.service"
    # FIFO(10) the stalld process so it doesn't get stalled by the hog process,
    # this is the default policy and priority of the stalld systemd service
    log "starting stalld in the background"
    # use a higher runtime ns for boosting, equal to 0.1s. With the default boost
    # timing, it will take multiple boosts to run the blocked task and the test
    # will take much longer
    chrt -f 10 stalld -v -t 30 -r 1000000 > >(tee -a "${OUTPUTFILE}") 2>&1 &
    STALLD_PID=$!
    log "STALLD_PID: $STALLD_PID"

    phase_end
}

test_run()
{
    local test_cpu stress_ng_pid stress_ng_cpu_pids timeout_pid
    declare -i runtime start_sec end_sec
    test_cpu=$(get_test_cpu)
    log "test_cpu: ${test_cpu}"

    for iter in $(seq 10); do
        phase_start "${TEST}: iter ${iter}" FAIL

        start_sec=$(date +%s)
        log "iter#${iter} starts at $start_sec seconds"

        log "starting stress-ng in the backgroud"
        stress-ng --sched fifo --sched-prio 1 --cpu 1 \
                  --timeout $MAX_RUNTIME \
                  --taskset $test_cpu > >(tee -a "${OUTPUTFILE}") 2>&1 &
        stress_ng_pid=$!

        # very likely the builtin stress-ng timeout will not work as intended,
        # so the following will serve as an effective timeout helper
        # NOTE: practically this won't be used if stalld is functioning well,
        # as the test usually takes about 40-50s to finish
        ( sleep $MAX_RUNTIME && pkill -e -9 stress-ng ) &
        timeout_pid=$!

        run "sleep 3s"  # give stress-ng few sec to warm up
        log "stress_ng_pid: $stress_ng_pid"
        run -l "ps $stress_ng_pid"

        ps aux --headers --lines 10 | tail > >(tee -a "${OUTPUTFILE}") 2>&1

        # this process blocks and has to get boosted to finish
        run "taskset -c $test_cpu echo Finished"

        end_sec=$(date +%s)
        runtime=$((end_sec - start_sec))
        log "iter#${iter} ends at $end_sec seconds"
        log "iter#${iter} finished in $runtime seconds"

        # runtime of each iteration should take no more than the threshold
        run "runtime_lt_threshold $runtime"

        # cleanup stress-ng threads by killing the stress-ng-cpu load thread,
        # not the main thread.  Killing the main thread alone does not
        # guarantee that the load thread will also be killed, whereas killing
        # the load thread will kill both threads effectively
        stress_ng_cpu_pids="$(pgrep -P $stress_ng_pid stress-ng-cpu)"
        for pid in $stress_ng_cpu_pids; do
            run -l "ps $pid"
            run "kill $pid"
        done

        kill $timeout_pid  # in case the timeout helper is still running

        run "sleep 3s"  # give stress-ng few sec to exit
        run "pgrep -a stress-ng" 1 "no stress-ng threads should be left"

        phase_end
    done
}

test_cleanup()
{
    phase_start_cleanup

    # in case of any potential zonbie stress-ng processes
    run -l "pkill -9 stress-ng"

    # stop stalld
    run "kill $STALLD_PID"
    run "sleep 10s"
    if [[ -f /proc/$STALLD_PID ]]; then
        log_warn "stalld did not exit greacefully - using SIGKILL instead"
        run "kill -9 $STALLD_PID"
    fi

    phase_end
}


kernel_automotive || rt_env_setup
test_setup
test_run
test_cleanup
