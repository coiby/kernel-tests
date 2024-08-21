#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#  Copyright Red Hat, Inc
#
#  SPDX-License-Identifier: GPL-2.0-or-later
#
# This script validates the kernel maximum stack size using tracer.
#
# First it checks if the stack tracer is enabled and exits if not.
#
# If enabled it checks the current stack_max_size value, and compares it against a predefined threshold.
#
# If the stack_max_size exceeds the threshold, a warning is logged, and the
# function responsible for the maximum stack usage is identified.
#
# Inputs:
#   /sys/kernel/tracing/stack_max_size
#   /sys/kernel/tracing/stack_trace
#   /proc/sys/kernel/stack_tracer_enabled
#
# Expected resluts:
#   [   INFO   ] :: stack_max_size (<size> bytes) is within the acceptable range.
#
# Signed-off-by: Li Wang <liwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Define the threshold value (e.g., 13kB in bytes)
THRESHOLD=${THRESHOLD:-13312}

STACK_TRACER_ENABLED="/proc/sys/kernel/stack_tracer_enabled"
STACK_MAX_SIZE="/sys/kernel/tracing/stack_max_size"
STACK_TRACE="/sys/kernel/tracing/stack_trace"

# ---------- Start Test -------------
rlJournalStart

    stack_results=${TMT_PLAN_DATA}/stack_results.log
    if [[ -f ${stack_results} ]]; then
        rlPhaseStart "WARN" "Check if tracer was disabled"
            if ! rlAssertNotGrep "RESULTS: WARN" ${stack_results}; then
                rlFail "stack tracer was not enabled."
            fi
        rlPhaseEnd
        rlPhaseStartTest "Check if stack size exceeded threshold"
            if ! rlAssertNotGrep "RESULTS: FAIL" ${stack_results}; then
                rlFail "stack_max_size exceeds the threshold ($THRESHOLD bytes)."
            fi
        rlPhaseEnd
    else
        rlLog "Stack trace was enabled and no test failures."
    fi

    rlPhaseStart "WARN" "Final check for tracer enabled"
        if ! rlAssertGrep 1 "$STACK_TRACER_ENABLED"; then
            rlFail "stack tracer is not enabled for final run."
            rlDie
        fi
    rlPhaseEnd

    rlPhaseStartTest "Final test of strack trace size"
        current_value=$(cat "$STACK_MAX_SIZE")
        if ! rlAssertLesser "Check if the current value exceeds the threshold" $current_value $THRESHOLD; then
            rlLog "Function responsible for maximum stack usage:"
            grep "$current_value" "$STACK_TRACE"
        fi
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
