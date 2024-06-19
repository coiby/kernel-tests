#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#  Copyright Red Hat, Inc
#
#  SPDX-License-Identifier: GPL-2.0-or-later
#
# This script validates the kernel maximum stack size using tracer.
#
# It enables the stack tracer, waits for some time to collect data, checks the
# current stack_max_size value, and compares it against a predefined threshold.
#
# If the stack_max_size exceeds the threshold, a warning is logged, and the
# function responsible for the maximum stack usage is identified.
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
	# Wait a moment to let the tracer collect data
	sleep 3

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
	rlLogInfo "Enabling stack tracer"
	echo 1 > "$STACK_TRACER_ENABLED"
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
