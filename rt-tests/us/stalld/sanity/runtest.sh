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

# Source rt common functions
. ../../../include/runtest.sh || exit 1

# Vars
export TEST="rt-tests/us/stalld/sanity"
STALLD_PID=""
MAX_RUNTIME=120  # seconds


runtime_lt_threshold() { (( runtime < MAX_RUNTIME )) && return 0 || return 1 ; }

dump_sysinfo()
{
    run -l "uname -a"
    run -l "cat /sys/devices/system/cpu/isolated"
    run -l "cat /proc/cmdline"
    run -l "cat /proc/cpuinfo"
}

test_setup()
{
    phase_start_setup

    run -l "systemctl status stalld.service"

    log "starting stalld in the background"
    # use a higher runtime ns for boosting, equal to 0.1s. With the default boost
    # timing, it will take multiple boosts to run the blocked task and the test
    # will take much longer
    stalld -v -t 30 -r 1000000 > >(tee -a "${OUTPUTFILE}") 2>&1 &
    STALLD_PID=$!
    log "STALLD_PID: $STALLD_PID"

    phase_end
}

test_run()
{
    local test_cpu stress_ng_pid stress_ng_load_pids timeout_pid
    declare -i runtime start_sec end_sec

    test_cpu=$(convert_number_range "$(get_isolated_cores)" | cut -d, -f1)
    log "test_cpu: ${test_cpu}"

    for iter in $(seq 10); do
        phase_start "${TEST}: iter ${iter}" FAIL

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

        ps aux --headers --lines 10 | tail -n 20 > >(tee -a "${OUTPUTFILE}") 2>&1

        start_sec=$(date +%s)
        log "iter#${iter} starts at $start_sec seconds"

        # this process blocks and has to get boosted to finish
        run "taskset -c $test_cpu echo Finished"

        end_sec=$(date +%s)
        runtime=$((end_sec - start_sec))
        log "iter#${iter} ends at $end_sec seconds"
        log "iter#${iter} finished in $runtime seconds"

        # runtime of each iteration should take no more than the threshold
        run "runtime_lt_threshold $runtime"

        # cleanup stress-ng threads by killing the load thread, not the main
        # thread.  Killing the main thread alone does not guarantee that the
        # load thread will also be killed, whereas killing the load thread will
        # kill both threads effectively
        stress_ng_load_pids="$(pgrep -d ' ' -P $stress_ng_pid)"
        if [[ -z $stress_ng_load_pids ]]; then
            log_warn "didn't found any stress-ng load threads!"
            run -l "pgrep -a stress-ng"
        else
            run -l "ps $stress_ng_load_pids"
            run "kill $stress_ng_load_pids"
        fi

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

do_test()
{
    test_setup
    test_run
    test_cleanup
}


kernel_automotive || rt_env_setup

if (( nrcpus < 2 )); then
    report_result "needs 2+ cpus for the test" SKIP 1
    exit 0
fi

if ! kernel_automotive && rhel_in_range 0 8.3; then
    report_result "stalld not supported" SKIP 2
    exit 0
fi

# make sure that at least one core is isolated
if (( RSTRNT_REBOOTCOUNT == 0 )); then
    if [[ -z "$(get_isolated_cores)" ]]; then
        # 1st run and no cpu isolation applied
        grep -oP 'isolcpus=[^ ]*' /proc/cmdline > F_ISOLCPUS_ORIGINAL

        log "No CPU isolation applied, isolating the last core and reboot"
        grubby --args="isolcpus=$((nrcpus-1))" --update-kernel=DEFAULT
        rstrnt-reboot
    else
        # CPU isolation is already applied, go ahead and start testing
        do_test
    fi
elif (( RSTRNT_REBOOTCOUNT == 1 )); then
    # 2nd run and the last core should've been isolated
    if [[ "$(get_isolated_cores)" != "$((nrcpus-1))" ]]; then
        dump_sysinfo
        run -l "cat F_ISOLCPUS_ORIGINAL"
        report_result "failed to isolate the last core" FAIL 3
        exit 0
    fi

    # go ahead and start testing
    log "Successfully isolated $(get_isolated_cores)"
    do_test

    # restore ``isolcpus=`` cmdline param
    log "Restore the isolcpus= cmdline parameter and reboot"
    isolcpus_original=$(cat F_ISOLCPUS_ORIGINAL)
    if [[ -z "${isolcpus_original}" ]]; then
        grubby --remove-args="isolcpus" --update-kernel=DEFAULT
    else
        grubby --args="${isolcpus_original}" --update-kernel=DEFAULT
    fi
    rstrnt-reboot
elif (( RSTRNT_REBOOTCOUNT == 2 )); then
    # 3rd run and ``isolcpus=`` should've been restored
    dump_sysinfo
    run -l "cat F_ISOLCPUS_ORIGINAL"
else
    log_error "System rebooted more than 2 times! (RSTRNT_REBOOTCOUNT: $RSTRNT_REBOOTCOUNT)"
    report_result "Abnormal reboots!" FAIL 4
fi
