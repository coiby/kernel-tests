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

: "${PIP_STRESS_RETRIES:=10}"
: "${PIP_STRESS_USLEEP:=500}"

export nrcpus rhel_x

if ! kernel_automotive; then
    rt_env_setup
fi


log "rt-tests/pi_stress Test Start"

if ! kernel_automotive; then
    declare pkg_name="rt-tests" && [ $rhel_x -ge 9 ] && pkg_name="realtime-tests"
    which pi_stress || yum install -y $pkg_name
fi

if [ -z "$PARAM_SEC" ]; then
    # For details: https://issues.redhat.com/browse/RHEL-34758
    # Limit the duration to 30s to avoid any rcu starvation warnings, the
    # default timeout for rcu stall is 60s.
    PARAM_SEC=30
fi
if [ -z "$PARAM_GROUPS" ]; then
    PARAM_GROUPS=1
fi

# Running pi_stress: suppress running output
oneliner "pi_stress --quiet --duration=$PARAM_SEC --groups=$PARAM_GROUPS"
# Running pi_stress: use SCHED_RR for test threads
oneliner "pi_stress --quiet --duration=$PARAM_SEC --groups=$PARAM_GROUPS --rr"
# Running pi_stress: set the number of inversion groups with CPU cores
oneliner "pi_stress --quiet --groups=$(( nrcpus )) --duration=30"

# Running pip_stress: used priority inheritance to handle an inversion

# Try up to N times for a successful pip_stress run
phase_start pip_stress
PIP_SUCCESS=0
for attempt in $(seq "$PIP_STRESS_RETRIES"); do
    log "Attempt $attempt"
    RESULT=$(run "pip_stress -u $PIP_STRESS_USLEEP")
    if [[ $(echo "$RESULT" | grep -c \
        "Successfully used priority inheritance to handle an inversion" ) -eq 1 ]]
    then
        PIP_SUCCESS=1
        break
    fi
    sleep 1
done

if [[ $PIP_SUCCESS -eq 1 ]] ; then
    log "pip_stress found an inversion"
    export PHASE_STATUS="PASS"
else
    log "pip_stress did not find an inversion"
    # Only fail we are running the automotive kernel or the PIP_STRESS_STRICT
    # environment variable is set
    if kernel_automotive || [[ -n "$PIP_STRESS_STRICT" ]]; then
        export PHASE_STATUS="FAIL"
    else
        export PHASE_STATUS="WARN"
    fi
fi
phase_end

exit 0
