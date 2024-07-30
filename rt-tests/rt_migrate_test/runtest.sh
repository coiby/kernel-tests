#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source rt common functions
. ../include/runtest.sh || exit 1
. ../../automotive/include/rhivos.sh || exit 1

function RunTest ()
{
    PROCS=$1

    log "Test Start Time: `date`"
    log "Running rt-migrate-test balance with $PROCS processors"
    oneliner "rt-migrate-test $PROCS" "rt-migrate-test balance"
    log "Test End Time: `date`"
}

function RunStress ()
{
    PROCS=$1

    log "Test Start Time: `date`" 
    log "Running rt-migrate-test stress with $PROCS processors"
    oneliner "rt-migrate-test $PROCS -l 1000" "rt-migrate-test stress"
    log "Test End Time: `date`"
}

# ---------- Start Test -------------
if ! kernel_automotive; then
    rt_env_setup
fi

# set default variables
NUMBERPROCS=$(/bin/cat /proc/cpuinfo | /bin/grep processor | wc -l)
SYSCPUS=$(expr `/bin/cat /proc/cpuinfo | /bin/grep processor | wc -l` + 1)

log "Number of Procs: $NUMBERPROCS / Running test with Procs: $SYSCPUS"
RunTest $SYSCPUS
RunStress $SYSCPUS
exit 0
