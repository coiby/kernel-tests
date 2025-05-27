#!/bin/bash

# Include BeakerLib environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# -------- CONFIG --------
LTP_REPO_URL="https://github.com/linux-test-project/ltp.git"
LTP_DIR="/tmp/ltp-src"
TESTS=("timer_create01" "futex_wait05")
TRACE_FUNCTIONS=(
  arch_timer_handler_phys
  arch_timer_set_next_event_phys
)
FTRACE_PATH="/sys/kernel/debug/tracing"

rlJournalStart
    rlPhaseStartSetup
        rlLog "Ensuring debugfs is mounted"
        rlRun "mount | grep -q 'debugfs on /sys/kernel/debug' || mount -t debugfs none /sys/kernel/debug"

        if [[ ! -d "$LTP_DIR" ]]; then
            rlLog "Cloning LTP source"
            rlRun "git clone --depth 1 $LTP_REPO_URL $LTP_DIR"
        else
            rlLog "Using cached LTP source"
        fi

        rlRun "cd $LTP_DIR"
        rlRun "make autotools"
        rlRun "./configure"
    rlPhaseEnd

    rlPhaseStartTest

        for TEST_NAME in "${TESTS[@]}"; do
            rlLog "[=== Running test: $TEST_NAME ===]"
            rlRun "cd $LTP_DIR"

            TEST_SRC=$(find . -type f -name "$TEST_NAME.c" | head -n1)

            if [[ -z "$TEST_SRC" ]]; then
                rlFail "Test source file $TEST_NAME.c not found"
                continue
            fi
            TEST_DIR=$(dirname "$TEST_SRC")
            rlRun "cd $TEST_DIR"
            rlLog "Compiling $TEST_NAME"
            rlRun "make $TEST_NAME"

            if [[ ! -x "$TEST_NAME" ]]; then
                rlFail "Test binary $TEST_NAME not built"
                continue
            fi

            # Setup ftrace
            rlLog "Preparing ftrace"
            echo function > "$FTRACE_PATH/current_tracer"
            echo > "$FTRACE_PATH/trace"
            echo > "$FTRACE_PATH/set_ftrace_filter"
            echo 0 > "$FTRACE_PATH/tracing_on"

            for fn in "${TRACE_FUNCTIONS[@]}"; do
                if grep -qw "$fn" "$FTRACE_PATH/available_filter_functions"; then
                    echo "$fn" >> "$FTRACE_PATH/set_ftrace_filter"
                else
                    rlLog "[WARN] Skipping $fn (not available on this kernel)"
                fi
            done

            rlLog "Running $TEST_NAME under ftrace"
            echo 1 > "$FTRACE_PATH/tracing_on"
            ./"$TEST_NAME"
            echo 0 > "$FTRACE_PATH/tracing_on"

            TRACE_LOG="/tmp/ftrace_${TEST_NAME}.log"
            cat "$FTRACE_PATH/trace" > "$TRACE_LOG"
            rlLog "Trace saved to $TRACE_LOG"

            ALL_PASS=true
            for fn in "${TRACE_FUNCTIONS[@]}"; do
                if grep -q "$fn" "$TRACE_LOG"; then
                    rlPass "$fn was called"
                else
                    rlFail "$fn was NOT called"
                    ALL_PASS=false
                fi
            done

            if [ "$ALL_PASS" = true ]; then
                rlPass "$TEST_NAME exercised arch_timer driver successfully"
            else
                rlFail "$TEST_NAME did not trigger all expected functions"
            fi
        done

    rlPhaseEnd

    rlPhaseStartCleanup
        rlLog "Cleaning up ftrace filters and traces"
        echo > "$FTRACE_PATH/set_ftrace_filter"
        echo > "$FTRACE_PATH/trace"

        rlLog "Removing compiled test binaries"
        for TEST_NAME in "${TESTS[@]}"; do
            find "$LTP_DIR" -type f -name "$TEST_NAME" -exec rm -f {} \;
        done
        rlLog "Cleanup complete"

    rlPhaseEnd

rlJournalPrintText
rlJournalEnd

