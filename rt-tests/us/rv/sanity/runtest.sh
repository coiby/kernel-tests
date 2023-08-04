#!/bin/bash

export TEST="rt-tests/us/rv/sanity"
export result_r="PASS"
. ../../../include/lib.sh

function check_status()
{
    if [ $? -eq 0 ]; then
        log_pass ":: $* :: PASS ::"
    else
        result_r="FAIL"
        log_fail ":: $* :: FAIL ::"
    fi
}

function runtest()
{
    if ! ( (( "$rhel_x" == 9 && "$rhel_y" >=3 )) || (( "$rhel_x" >= 10 )) ); then
        log "rv is only supported for RHEL >= 9.3"
        rstrnt-report-result $TEST "SKIP" 0
        exit 0
    fi

    log "Package rv sanity tests"
    rpm -q --quiet rv || dnf install -y rv || {
        log "Install rv failed"
        rstrnt-report-result $TEST "FAIL" 1
        exit 1
    }

    log "## rv --help: check rv help page ##"
    rv --help
    check_status "rv --help"

    log "## rv list: list available monitors ##"
    rv list
    check_status "rv list"
    ral=$(rv list | awk -F' ' '{print $1}')
    log "Available monitors: $ral"

    if [ $result_r = "PASS" ]; then
        log_pass "Overall result: PASS"
        rstrnt-report-result $TEST "PASS" 0
    else
        log_fail "Overall result: FAIL"
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

runtest
