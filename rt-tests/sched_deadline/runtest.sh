#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh || exit 1
: ${OUTPUTFILE:=runtest.log}

# Source rt common functions
. ../include/runtest.sh || exit 1

TEST="rt-tests/sched_deadline"

ENABLE_HRTICK=${ENABLE_HRTICK:-0}

function enable_hrtick()
{
    [ "$ENABLE_HRTICK" = 0 ] && return

    # https://bugzilla.redhat.com/show_bug.cgi?id=2095089#c6
    if test -f /sys/kernel/debug/sched/features; then
        sched_feature_file="/sys/kernel/debug/sched/features"
    elif test -f /sys/kernel/debug/sched_features; then
        sched_feature_file="/sys/kernel/debug/sched_features"
    fi

    hrtick=$(awk -v RS=" " '/HRTICK$/ {print}' $sched_feature_file)
    hrtick_dl=$(awk -v RS=" " '/HRTICK_DL$/ {print}' $sched_feature_file)
    echo "origin: hrtick=$hrtick, hrtick_dl=$hrtick_dl"

    if [ -n "$hrtick_dl"  ]; then
        echo Setting hrtick_dl
        echo HRTICK_DL > $sched_feature_file
        grep -w HRTICK_DL $sched_feature_file && echo succeeded
        cleanup=hrtick_dl
    elif [ -n "$hrtick" ]; then
        echo Setting hrtick
        echo HRTICK > $sched_feature_file
        grep -w HRTICK $sched_feature_file && echo succeeded
        cleanup=hrtick
    else
        echo "hrtick is not supported! skip setting"
    fi
}

function restore_hrtick()
{
    [ "$ENABLE_HRTICK" = 0 ] && return
    [ -n "$cleanup" ] && echo ${!cleanup} > $sched_feature_file
    grep -w ${!cleanup} $sched_feature_file && echo succeeded
}

function runtest()
{
    echo "clean the dmesg log" | tee -a $OUTPUTFILE
    dmesg -c

    deadline_test | tee -a $OUTPUTFILE
    deadline_test -t 1 -i 10000 | tee -a $OUTPUTFILE

    dmesg | grep 'Call Trace'
    if [ $? -eq 0 ]; then
        rstrnt-report-result $TEST "FAIL" "1"
    else
        rstrnt-report-result $TEST "PASS" "0"
    fi
}

if ! kernel_automotive; then
    rt_env_setup
fi
enable_hrtick
runtest
restore_hrtick
exit 0
