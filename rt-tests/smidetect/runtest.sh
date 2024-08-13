#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh || exit 1
: ${OUTPUTFILE:=runtest.log}

# Source rt common functions
. ../include/runtest.sh || exit 1

export DURATION=${DURATION:-10m}
export LATCHECK=${LATCHECK:-0}
export HARDLIMIT=${HARDLIMIT:-200us}

function RunTest ()
{
    log "Test Start Time: $(date)" | tee -a $OUTPUTFILE

    run "hwlatdetect \
        --duration=$DURATION \
        --window=1s \
        --width=500ms \
        --threshold=10us \
        --hardlimit=$HARDLIMIT \
        --debug" \
        2>&1 | tee -a $OUTPUTFILE
    log "RET_CODE=${PIPESTATUS[0]}"

    if [ $LATCHECK -eq 0 ]; then
        if ! grep -qE '(Traceback|Error)' $OUTPUTFILE && {
                # return code should at least be 0 or 1 to pass functional check
                [ $RET_CODE -eq 0 ] || [ $RET_CODE -eq 1 ]
            }; then
            rstrnt-report-result "smidetect(hwlatdetect) Passed - functional verification" "PASS" 0
        else
            rstrnt-report-result "smidetect(hwlatdetect) Failed - functional verification" "FAIL" 1
        fi
    else
        if [ $RET_CODE -eq 0 ]; then
            rstrnt-report-result "smidetect(hwlatdetect) Passed - latency verification" "PASS" 0
        else
            rstrnt-report-result "smidetect(hwlatdetect) Failed - latency verification" "FAIL" 1
        fi
    fi

    log "Test End Time: $(date)" | tee -a $OUTPUTFILE
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
