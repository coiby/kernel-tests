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

if ! kernel_automotive; then
    rt_env_setup
fi

export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')
export rhel_minor=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $2}')
declare num_cpus=$(grep -c ^processor /proc/cpuinfo)

echo "--- Test Start ---" | tee -a $OUTPUTFILE

if ! kernel_automotive; then
    declare pkg_name="rt-tests" && [ $rhel_major -ge 9 ] && pkg_name="realtime-tests"
    which pi_stress || yum install -y $pkg_name
fi

if [ -z "$PARAM_SEC" ]; then
    PARAM_SEC=300
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

echo "Running pi_stress --quiet --groups=$(( num_cpus )) --duration=30" | tee -a $OUTPUTFILE
pi_stress --quiet --groups=$(( num_cpus )) --duration=30 | tee -a $OUTPUTFILE
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
