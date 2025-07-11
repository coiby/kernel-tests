#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rtla/validate_cpus_for_osnoise"
# minimum number of processors required
export MIN_CPU_REQUIRED=128

function runtest()
{
    # Verify rtla is installed
    oneliner "yum install -y rtla"

    cd /sys/kernel/tracing/osnoise || {
        log "Error: Cannot change directory to /sys/kernel/tracing/osnoise"
        exit 1
    }

    phase_start_test "Generate and write CPUs string"
    cpus=$(seq -s, 0 100)
    log "Length of CPUs string: ${#cpus}"

    err_msg=$( { echo "$cpus" > cpus; } 2>&1 )

    if [[ -z "$err_msg" ]]; then
        log_pass "Successfully wrote to 'cpus'"
    elif [[ "$err_msg" == *"Invalid argument"* ]]; then
        log_fail "Failed to write to 'cpus': Invalid argument"
    else
        log_fail "Failed to write to 'cpus': $err_msg"
    fi
    phase_end
}

# Only run on 9.7+
if rhel_in_range 0 9.6; then
    rstrnt-report-result "Bug fix in RHEL-9.7+ and RHEL-10.1+ -- skipping test case" "SKIP" 0
    exit 0
fi

# check if the number of CPU processors is >= MIN_CPU_REQUIRED
cpu_count=$(grep -c ^processor /proc/cpuinfo)
log "Detected $cpu_count processors."
if (( cpu_count < MIN_CPU_REQUIRED )); then
    rstrnt-report-result "CPU count is less than $MIN_CPU_REQUIRED. At least $MIN_CPU_REQUIRED processors are required" "SKIP" 0
    exit 0
fi

runtest
exit 0
