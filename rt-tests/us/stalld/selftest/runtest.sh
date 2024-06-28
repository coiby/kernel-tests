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

function run_test ()
{
    log "Test Start Time: $(date)"
    selftest=0

    phase_start_test "Running selftest"
    # Compile selftest
    run "gcc -g -Wall -pthread -o selftest selftest.c -lpthread"
    run "./selftest -d"
    selftest=${PIPESTATUS[0]}

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