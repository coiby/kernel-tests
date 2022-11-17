#!/bin/bash

TEST="general/time/selftest"
. ../../include/lib.sh || exit 1

K_ITEM=${K_ITEM:-""}

function run_modules()
{
    test_path=$BUILD_PATH/tools/testing/selftests/$1
    pushd $test_path
    make
    for file in ./*; do
        if test -x $file; then
            echo "$file:"
            ./$file | tee -a $file.log
            if [ $? -ne 0 ]; then
                rstrnt-report-result "$file" "FAIL" 1
            else
                rstrnt-report-result "$file" "PASS" 0
            fi
            rstrnt-report-log -l $file.log
        fi
    done
    popd
}

function run_selftests()
{
    prepare_running_kernel_src
    BUILD_PATH="linux-*"

    if [[ -z $K_ITEM ]]; then
        echo "Please pass the test items in $K_ITEM that under tools/testing/selftests/"
        rstrnt-report-result "$TEST" "SKIP" 0
        exit 0
    fi

    for item in $K_ITEM; do
        run_modules $item
        sleep 10
    done
}

run_selftests
exit 0
