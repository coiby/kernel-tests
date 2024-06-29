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
THRESHOLD=13312

STACK_TRACER_ENABLED="/proc/sys/kernel/stack_tracer_enabled"
STACK_MAX_SIZE="/sys/kernel/tracing/stack_max_size"
STACK_TRACE="/sys/kernel/tracing/stack_trace"

function validate_kernel_max_stack_size()
{
    # Read the current stack_max_size value
    current_value=$(cat "$STACK_MAX_SIZE")
    cat "$STACK_TRACE" > STACK_TRACE_LOG

    # Check if the current value exceeds the threshold
    if [[ $current_value -gt $THRESHOLD ]]; then
        rlLogError "stack_max_size ($current_value bytes) exceeds the threshold ($THRESHOLD bytes)."
        rlLogInfo "Function responsible for maximum stack usage:"
        grep "$current_value" STACK_TRACE_LOG
    else
        rlLogInfo "stack_max_size ($current_value bytes) is within the acceptable range."
    fi
}

# ---------- Start Test -------------
rlJournalStart

rlPhaseStartSetup
    rlLogInfo "Confirming stack tracer is enabled."
    if ! rlAssertGrep 1 "$STACK_TRACER_ENABLED"; then
        rlLogError "stack tracer is not enabled."
        rlPhaseEnd
        rlJournalEnd
        exit 1
    fi
rlPhaseEnd

rlPhaseStartTest
    validate_kernel_max_stack_size
rlPhaseEnd

rlPhaseStartCleanup
    rlLogInfo "Disabling stack tracer"
    echo 0 > "$STACK_TRACER_ENABLED"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
