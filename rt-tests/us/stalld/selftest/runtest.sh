#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

function install_and_start_stalld()
{
    # Only run on 8.4 and up
    if rhel_in_range 0 8.3; then
        rstrnt-report-result "stalld is only supported for RHEL >= 8.4 and up" "SKIP" 5
        exit 0
    fi

    # Verify stalld is installed
    oneliner "yum install -y stalld"
    # Enable stalld if needed
    oneliner "systemctl start stalld.service"
}

function fair_save()
{
    # el10 and above
    if [[ -e /sys/kernel/debug/sched/fair_server ]]; then
       cp -r /sys/kernel/debug/sched/fair_server /tmp/fair_save
    fi
}

function fair_restore_free()
{
    if [[ -e /tmp/fair_save ]]; then
        pushd /sys/kernel/debug/sched/fair_server/
        for a in * ; do
            echo "/tmp/fair_save/$a/runtime" > "/sys/kernel/debug/sched/fair_server/$a/runtime"
        done
        popd
        rm -rf /tmp/fair_save
    fi
}

function fair_disable()
{
    if [[ -e /sys/kernel/debug/sched/fair_server ]]; then
        pushd /sys/kernel/debug/sched/fair_server/
        for a in * ; do echo 0 > "$a/runtime" ; done
        popd
    fi
}

function run_test ()
{
    log "Test Start Time: $(date)"
    selftest=0

    phase_start_test "Running selftest"
    # Compile selftest
    run "gcc -g -Wall -pthread -o selftest selftest.c -lpthread"
    fair_save
    fair_disable
    run "./selftest -d"
    selftest=${PIPESTATUS[0]}
    fair_restore_free

    if [ "$selftest" -eq 0 ]; then
        rstrnt-report-result "selftest PASS" "PASS" 0
    else
        rstrnt-report-result "selftest FAIL" "FAIL" 1
    fi
    phase_end

    log "Test End Time: $(date)"
}

function stop_stalld()
{
    # Stoping stalld
    oneliner "systemctl stop stalld.service"
}

# ---------- Start Test -------------

install_and_start_stalld
run_test
stop_stalld
exit 0
