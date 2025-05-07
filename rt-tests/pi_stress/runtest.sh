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

# Source rt common functions
. ../include/runtest.sh || exit 1

export nrcpus rhel_x rhel_y

if ! kernel_automotive; then
    rt_env_setup
fi

if ! command -v pi_stress; then
    log "Command pi_stress not found"
    exit 1
fi

# Limit the duration to 30s to avoid any rcu starvation warnings, the
# default timeout for rcu stall is 60s, see RHEL-34758
: ${PI_STRESS_DURATION:=30}
: ${PI_STRESS_GROUPS:=1}
# Running pi_stress: suppress running output
oneliner "pi_stress --quiet --duration=$PI_STRESS_DURATION --groups=$PI_STRESS_GROUPS"
# Running pi_stress: use SCHED_RR for test threads
oneliner "pi_stress --quiet --duration=$PI_STRESS_DURATION --groups=$PI_STRESS_GROUPS --rr"
# Running pi_stress: set the number of inversion groups with CPU cores
oneliner "pi_stress --quiet --groups=$(( nrcpus )) --duration=30"

if [[ -z "${PIP_STRESS_USLEEP}" ]]; then
    # aarch64 and rt-debug requires more sleep to get an inversion triggered
    if uname -r | grep -qE "aarch64|rt.*debug"; then
        PIP_STRESS_USLEEP=10000
    else
        # defaults in pip_stress is 500, and we still see failures on certain
        # hardwares occasionally, make it 5000
        PIP_STRESS_USLEEP=5000
    fi
fi
OPT_USLEEP="-u $PIP_STRESS_USLEEP"

# Running pip_stress: used priority inheritance to handle an inversion
phase_start_test "pip_stress $OPT_USLEEP"
if pip_stress -h | grep -q '\--usleep'; then
    # Use the official pip_stress when usleep option is available
    pip_stress_cmd=pip_stress
else
    # Build pip_stress with usleep support when n/a in official pkg
    build_dir=$(mktemp -d)
    rt_tests_repo="https://gitlab.com/redhat/centos-stream/tests/kernel/core/rt-tests.git"
    # the commit that adds the usleep option
    usleep_hash="eea8da1647c3f7d26f3aae607475266112ab79b1"
    # all the source files used by pip_stress
    files="src/pi_tests/pip_stress.c src/include/pip_stress.h src/include/rt-error.h"
    if ((rhel_x == 7)); then
        ref="tags/v1.8"
    elif ((rhel_x == 8)); then
        ref="tags/v2.6"
    elif ((rhel_x == 9 && rhel_y < 6)); then
        ref="tags/v2.8"
    else
        ref="main"
    fi
    run "git clone $rt_tests_repo $build_dir"
    pushd $build_dir
    run "git checkout $ref"
    run "git checkout $usleep_hash -- $files"
    run "make pip_stress"
    if run "test -x ./pip_stress"; then
        pip_stress_cmd=$(realpath ./pip_stress)
    else
        log "Failed to build pip_stress with usleep support!"
        phase_end
        exit 1
    fi
    popd
fi

run "$pip_stress_cmd $OPT_USLEEP" 2>&1 | tee pip_stress.log
# the return code doesn't reflect if an inversion was triggered
run "grep Successfully pip_stress.log" 0 "Check if inversion was triggered"
phase_end

test_finish

exit 0
