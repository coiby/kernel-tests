#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Enable TMT testing for RHIVOS
. ../../../../automotive/include/rhivos.sh || exit 1

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/stalld/sanity"
export STRESS_NG_TIMEOUT=${STRESS_NG_TIMEOUT:-60}  # seconds
export nrcpus rhel_x

dump_sysinfo() {
    run -l "uname -a"
    run -l "cat /sys/devices/system/cpu/isolated"
    run -l "cat /proc/cmdline"
    run -l "cat /proc/cpuinfo"
}

to_cpumask() {
    # convert cpu number to cpumask
    local cpu=$1
    local group=$((cpu / 32))
    local cpu_round=$((cpu % 32))
    local cpumask=$(printf "%x" "$((1 << cpu_round))")

    for ((i=0; i<group; i++)); do
        cpumask="${cpumask},00000000"
    done

    echo "$cpumask"
}

save_cls_pri() {
    run "ps -o cls=,pri= $1 > init_cls_pri_$1"
}

restore_cls_pri() {
    local pid=$1
    local init_file=init_cls_pri_$pid

    if [[ ! -f $init_file ]]; then
        log_fail "no such file: $init_file"
        return 1
    elif [[ ! -s $init_file ]]; then
        log_fail "empty file: $init_file"
        return 1
    fi
    read -r cls pri < "$init_file"

    local opt_cls=""
    case "$cls" in
        TS)  opt_cls="-o"; pri=0 ;;
        FF)  opt_cls="-f" ;;
        RR)  opt_cls="-r" ;;
        B)   opt_cls="-b"; pri=0 ;;
        IDL) opt_cls="-i"; pri=0 ;;
        *)   log_fail "unknown cls $cls"; return 1 ;;
    esac
    run "chrt $opt_cls -p $pri $pid"
}

tune_kthreads() {
    # raise the priority of kthreads to prevent them being starved by the
    # FIFO(1) stress-ng loads, otherwise sleeping processes won't be able to
    # wakeup as the timers won't fire; and the `--timeout` option in the
    # stress-ng command won't be as effective either as it essentially relies on
    # the timer to arrive.
    if ((rhel_x >= 10)); then
        ktimers_pid=$(pgrep "ktimers/${test_cpu}$")
        if [[ "$1" == "set" ]]; then
            save_cls_pri "$ktimers_pid"
            run "chrt --fifo --pid 5 $ktimers_pid"
        elif [[ "$1" == "unset" ]]; then
            restore_cls_pri "$ktimers_pid"
        fi
    else
        kworker_pids=$(pgrep "kworker/${test_cpu}:")
        if [[ "$1" == "set" ]]; then
            for kworker_pid in $kworker_pids; do
                save_cls_pri "$kworker_pid"
                run "chrt --fifo --pid 5 $kworker_pid"
            done
        elif [[ "$1" == "unset" ]]; then
            for kworker_pid in $kworker_pids; do
                restore_cls_pri "$kworker_pid"
            done
        fi
    fi
}

test_setup() {
    phase_start_setup

    # build the starver binary
    run "gcc starver.c -o starver"
    if [[ -x starver ]]; then
        run "cp starver /usr/local/bin"
    else
        log "failed to build starver"
        exit 1
    fi

    # start the stalld daemon
    run -l "systemctl status stalld.service"
    log "starting stalld in the background"
    stalld --boost_period 200000000 \
           --boost_runtime 1000000 \
           --boost_duration 1 \
           --starving_threshold 1 \
           --verbose > >(tee -a "${OUTPUTFILE}") 2>&1 &
    stalld_pid=$!
    log "stalld_pid: $stalld_pid"

    # select the first isolated core as the test cpu
    test_cpu=$(convert_number_range "$(get_isolated_cores)" | cut -d, -f1)
    log "test_cpu: ${test_cpu}"

    # change prio of some kthreads
    tune_kthreads "set"

    # half the timeout is the time we leave for the starver process to run, so
    # make sure there are at least 30 seconds otherwise the starver won't be
    # able to complete
    if (( STRESS_NG_TIMEOUT < 60 )); then
        log_warn "STRESS_NG_TIMEOUT should be at least 60 seconds"
        log_warn "increasing STRESS_NG_TIMEOUT to 60 seconds"
        export STRESS_NG_TIMEOUT=60
    fi

    phase_end
}

test_run() {
    phase_start_test

    # start the starver process
    taskset -c "$test_cpu" starver > >(tee starver.log) 2>&1 &
    starver_pid=$!
    log "starver_pid: $starver_pid"

    # give the starver some cycles to run
    sleep 0.5s

    # set tracing filters
    tracing_dir="/sys/kernel/debug/tracing"
    run "echo 0 > ${tracing_dir}/tracing_on"
    run "echo > ${tracing_dir}/trace"
    tracing_cpumask=$(to_cpumask "$test_cpu")
    run "echo ${tracing_cpumask} > ${tracing_dir}/tracing_cpumask"
    run "echo 1 > ${tracing_dir}/events/sched/sched_switch/enable"
    run "echo ${starver_pid} > ${tracing_dir}/set_ftrace_pid"

    # start the stress-ng process
    stress-ng --sched fifo --sched-prio 1 --cpu 1 \
              --timeout "$STRESS_NG_TIMEOUT" \
              --taskset "$test_cpu" > >(tee -a "${OUTPUTFILE}") 2>&1 &
    stress_ng_pid=$!
    log "stress_ng_pid: $stress_ng_pid"

    # wait for the stress-ng process to warm up
    sleep 3s

    # start tracing
    run "echo 1 > ${tracing_dir}/tracing_on"
    # stop tracing before stress-ng is timeout
    sleep $((STRESS_NG_TIMEOUT / 2))
    run "echo 0 > ${tracing_dir}/tracing_on"
    run "cat ${tracing_dir}/trace > trace.txt"

    # wait for the stress-ng process to exit
    sleep $((STRESS_NG_TIMEOUT / 2))

    # check if the starver process was scheduled
    run "grep starver-${starver_pid} trace.txt"

    # restore the tracing filters
    run "echo > ${tracing_dir}/trace"
    run "echo 0 > ${tracing_dir}/events/sched/sched_switch/enable"
    run "echo 0 > ${tracing_dir}/set_ftrace_pid"

    phase_end
}

test_cleanup() {
    phase_start_cleanup

    # stop the stress-ng load processes if there are any; send the signal
    # directly to the load processes, not the main thread, which might not
    # be able to respond to the signal immediately
    stress_ng_load_pids="$(ps --ppid ${stress_ng_pid} -o pid= | xargs)"
    if [[ -z $stress_ng_load_pids ]]; then
        log "didn't found any stress-ng load threads"
    else
        run -l "ps $stress_ng_load_pids"
        run "kill $stress_ng_load_pids"
    fi

    run -l "kill ${stalld_pid}" 0 "stop the stalld process"
    run -l "kill ${starver_pid}" 0 "stop the starver process"

    tune_kthreads "unset"

    # upload the logs
    rstrnt-report-log -l trace.txt
    rstrnt-report-log -l starver.log

    phase_end
}

do_test() {
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
    log_fail "System rebooted more than 2 times! (RSTRNT_REBOOTCOUNT: $RSTRNT_REBOOTCOUNT)"
    report_result "Abnormal reboots!" FAIL 4
fi
