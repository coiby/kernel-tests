#!/bin/bash

# Source rt common functions
. ../../../include/runtest.sh || exit 1

export TEST="rt-tests/us/rtla/validate_cpus_for_osnoise"

function runtest()
{
    oneliner "yum install -y rtla"

    cd /sys/kernel/tracing/osnoise || {
        log_fail "Cannot change directory to /sys/kernel/tracing/osnoise"
        return 1
    }

    # shellcheck disable=SC2154
    phase_start_test "Detected $nrcpus processors. Write full CPU list to osnoise/cpus"
    # Generate cpus string: 0,1,...,$((nrcpus-1))
    max_cpu=$((nrcpus - 1))
    cpus=$(seq -s, 0 "$max_cpu")

    log "Generated CPUs string of length ${#cpus}"
    run "echo \"$cpus\" > cpus"
    run "cat cpus"
    phase_end
}

# Only run on 9.7+ and 10.1+
if rhel_in_range 0 9.6 || rhel_in_range 10.0 10.0; then
    rstrnt-report-result "Known bug fixed in RHEL 9.7+ and 10.1+. Skipping test." "SKIP" 0
    exit 0
fi

runtest
exit 0
