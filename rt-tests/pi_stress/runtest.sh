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

export TEST="rt-tests/pi_stress"
export nrcpus rhel_x

if ! kernel_automotive; then
    rt_env_setup
fi


echo "--- Test Start ---" | tee -a $OUTPUTFILE

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

echo "Running pi_stress --quiet --duration=$PARAM_SEC --groups=$PARAM_GROUPS" | tee -a $OUTPUTFILE
pi_stress --quiet --duration=$PARAM_SEC --groups=$PARAM_GROUPS | tee -a $OUTPUTFILE
if [ $? -eq 0 ]; then
    rstrnt-report-result "pi_stress SCHED_FIFO" "PASS" 0
else
    rstrnt-report-result "pi_stress SCHED_FIFO" "FAIL" 1
fi

echo "Running pi_stress --quiet --duration=$PARAM_SEC --groups=$PARAM_GROUPS --rr" | tee -a $OUTPUTFILE
pi_stress --quiet --duration=$PARAM_SEC --groups=$PARAM_GROUPS --rr | tee -a $OUTPUTFILE
if [ $? -eq 0 ]; then
    rstrnt-report-result "pi_stress SCHED_RR" "PASS" "0"
else
    rstrnt-report-result "pi_stress SCHED_RR" "FAIL" "1"
fi

echo "Running pi_stress --quiet --groups=$(( nrcpus )) --duration=30" | tee -a $OUTPUTFILE
pi_stress --quiet --groups=$(( nrcpus )) --duration=30 | tee -a $OUTPUTFILE
if [ $? -eq 0 ]; then
    rstrnt-report-result "pi_stress maxcpu" "PASS" "0"
else
    rstrnt-report-result "pi_stress maxcpu" "FAIL" "1"
fi

echo "Running pip_stress" | tee -a $OUTPUTFILE
pip_stress | tee -a $OUTPUTFILE
if [ $? -eq 0 ]; then
    rstrnt-report-result "pip_stress" "PASS" "0"
else
    rstrnt-report-result "pip_stress" "FAIL" "1"
fi


exit 0
