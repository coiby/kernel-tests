#!/bin/bash

TEST="general/ftrace/sanity/selftest"
. ../../../include/lib.sh || exit 1

function run_selftest()
{
    prepare_running_kernel_src
    BUILD_PATH="linux-*"

    ftrace_path=$BUILD_PATH/tools/testing/selftests/ftrace
    if ! test -f $ftrace_path/ftracetest; then
        echo "ftracetest not exist"
        rstrnt-report-result $TEST "FAIL" 1
        exit 1
    fi

    pushd $ftrace_path
    ./ftracetest
    sleep 10
    if grep "\[FAIL\]" logs/*/ftracetest.log; then
        echo "Failed! Please check the logs for details"
        rstrnt-report-result $TEST "FAIL" 1
    else
        echo "PASS"
        rstrnt-report-result $TEST "PASS" 0
    fi
    for log in logs/*/*; do
        rstrnt-report-log -l $log
    done
    popd
}

run_selftest
exit 0
