#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Enable TMT testing for RHIVOS
. ../../automotive/include/include.sh || exit 1
: ${OUTPUTFILE:=runtest.log}

# Source rt common functions
. ../include/runtest.sh || exit 1

export TEST="rt-tests/smidetect"
export DURATION=${DURATION:-10m}
export LATCHECK=${LATCHECK:-0}
export HARDLIMIT=${HARDLIMIT:-200us}

function RunTest ()
{
    echo "Test Start Time: $(date)" | tee -a $OUTPUTFILE

    hwlatdetect \
        --duration=$DURATION \
        --window=1s \
        --width=500ms \
        --threshold=10us \
        --hardlimit=$HARDLIMIT \
        --debug \
        2>&1 | tee -a $OUTPUTFILE
    RET_CODE=${PIPESTATUS[0]}

    # The numeric values below assume we are dealing with user seconds.
    VAL=$(grep 'Max Latency' $OUTPUTFILE | awk -F: '{print $2}')
    MAXLAT=$(grep 'Max Latency' $OUTPUTFILE | awk -F: '{gsub(/ /,"");gsub(/[a-z]+/,"");print $2}')
    LIMIT_NUMERIC=$(echo $HARDLIMIT | awk -F[a-z] '{print $1}')

    if [ $LATCHECK -eq 0 ]; then
        # User chooses not to review max latency, so set pass/fail based on exit
        # status of smidetect
        if [ $RET_CODE -eq 0 ]; then
            echo "smidetect(hwlatdetect) Passed - functional verification: " | tee -a $OUTPUTFILE
            rstrnt-report-result "$TEST" "PASS" 0
        else
            echo "smidetect(hwlatdetect) Failed - functional verification: " | tee -a $OUTPUTFILE
            rstrnt-report-result "$TEST" "FAIL" 1
        fi
    else
        # Set result to pass only if max lat remained under HARDLIMIT
        if [[ $VAL == ' Below threshold' ]] || (($MAXLAT <= $LIMIT_NUMERIC)); then
            echo "smidetect(hwlatdetect) Passed - latency verification: " | tee -a $OUTPUTFILE
            rstrnt-report-result "$TEST" "PASS" 0
        else
            echo "smidetect(hwlatdetect) Failed - latency verification: " | tee -a $OUTPUTFILE
            rstrnt-report-result "$TEST" "FAIL" 1
        fi
    fi

    echo "Test End Time: $(date)" | tee -a $OUTPUTFILE
}

# ---------- Start Test -------------
if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    if ! kernel_automotive; then
        rt_env_setup
    fi
    RunTest
    # reboot after test run because smidetect can leave residual SMI/SMM
    # mods that impact future test cases such as stalld
    rstrnt-reboot
fi

exit 0
