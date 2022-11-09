#!/bin/bash
function test_max_threads()
{
    local setval=$1
    local tst_type=$2

    if [[ $tst_type == min ]]; then
        echo $setval > /proc/sys/kernel/threads-max
        local tmp=$?
        echo $ori > /proc/sys/kernel/threads-max
        rlAssertEquals "echo $setval > /proc/sys/kernel/threads-max should succeed" $tmp "0"
    elif [[ $tst_type == max ]]; then
        rlRun "echo $setval > /proc/sys/kernel/threads-max" 0 "$setval is within limit and should be set successfully"
        local temp=$(cat /proc/sys/kernel/threads-max)
        rlAssertEquals "$setval is the maximum that could be set up successfully" $temp $setval
    elif [[ $tst_type == out ]]; then
        rlRun -l "echo $setval > /proc/sys/kernel/threads-max" 1-255 "$setval is out of boundary"
    else
        rlReport "bz1771270" WARN
    fi
}

function bz1771270()
{
    local rh=$(uname -r | grep -Eo 'el[0-9]*' | grep -Eo '[0-9]*')
    local ver=$(uname -r | grep -Eo '\-[0-9]*.')
    local ker=${ver:1:len-1}
    local ori=$(cat /proc/sys/kernel/threads-max)

    if ((rh == 7)); then
        test_max_threads 1 min

        test_max_threads 2147483648 out

        test_max_threads 2147483647 max
    elif ((ker < 163 && rh == 8)); then
        test_max_threads 1 out

        test_max_threads 20 min

        test_max_threads 1073741824 out
    elif (((ker >= 163 && rh == 8) || (rh > 8))); then
        test_max_threads 1 min

        test_max_threads 1073741824 out

        test_max_threads 1073741823 max
    else
        rlReport "bz1771270" WARN
    fi
    sysctl kernel.threads-max=$ori
}