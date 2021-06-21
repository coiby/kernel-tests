#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc 
#
#   SPDX-License-Identifier: GPL-3.0-or-later  
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source rt common functions
. ../include/runtest.sh || exit 1

TEST="rt-tests/sched_deadline"

function runtest()
{
    result_r="PASS"

    echo "clean the dmesg log" | tee -a $OUTPUTFILE
    dmesg -c

    deadline_test -t 1 | tee -a $OUTPUTFILE
    deadline_test -t 1 -i 10000 | tee -a $OUTPUTFILE

    dmesg | grep 'Call Trace'
    if [ $? -eq 0 ]; then
        rstrnt-report-result $TEST "FAIL" "1"
    else
        rstrnt-report-result $TEST "PASS" "0"
    fi
}

rt_env_setup
runtest
exit 0
