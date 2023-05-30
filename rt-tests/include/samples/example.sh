#!/bin/bash

. ../lib.sh



function return100() { return 100 ; }


function dummy_tmpdir()
{
    local tmpdir=$(mktemp -d) ret=0
    pushd ${tmpdir} || ((ret++))
    pwd
    popd || ((ret++))
    return $ret
}


# examples of log() functions
function test_f_log()
{
    phase_start "log() usage examples" WARN

    log_begin "Warming up..."
    log_pass "Mom! Door's open!"
    log_fail "Cannot find the confidential files anywhere..."
    log_warn "Self destruct in T-minus 5, 4..."
    log_end "Mission aborted"

    sleep 1s

    log -l SKIP "RT Kernel not supported on aarch64 yet"
    log -l ERROR "Upgrade your system before booting the kernel"
    log -l OXFORD "Where people craft dictionaries of all sorts"

    sleep 1s

    log_raw "log#1: No format chars will be added automatically, '\\\n' included"
    log_raw "log#2: This log has an ending new line char\n"
    log_raw "log#3: Five new lines:\n\n\n\n\n"
    log_raw "log#4: Five new lines end here"

    sleep 1s

    log_raw "log#5: \e[1;32mColors chars are also interpretable\e[00m\n"

    phase_end
}


# examples of run() functions
function test_f_run()
{
    phase_start "run() usage examples" FAIL

    run "who am i"
    run "echo ${PWD/${HOME}}"
    run "command_not_exist" 0
    run "command_not_exist" 127
    run "sleep 1s"
    run "return100" 0 "Function that returns 100 exit code"
    run "return100" 0,100 "Function that returns 100 exit code"
    run "! :" 1 "Revert true value"
    run "command --option-not-exist" 2 "Expect 2 as return code"

    run --logonly "cat /etc/hostname"
    run --logonly "cat /etc/hosts"

    phase_end
}


# examples of oneliner() function
function test_f_oneliner()
{
    log_raw "\n\n\n\e[1;32m>>>>> oneliner() usage examples <<<<<\e[00m\n\n\n"
    oneliner "return100" "Test function return100"
    oneliner "dummy_tmpdir" "Dummy Test Example with mktemp"
}


test_f_log
test_f_run
test_f_oneliner

test_finish
