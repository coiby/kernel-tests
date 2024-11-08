#!/bin/bash

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh

# Source rt common functions
. ../include/lib.sh || exit 1

export rhel_x

if ! kernel_automotive; then
    declare pkg_name="rt-tests" && (( rhel_x >= 9 )) && pkg_name="realtime-tests"
    run "yum install -y $pkg_name"
fi

log "Test the default options of ssdd"
oneliner "timeout --preserve-status --verbose 3m ssdd"

log "Stress test ssdd with 100 forks and 10000 iters"
oneliner "timeout --preserve-status --verbose 4m ssdd --forks=100 --iters=10000"
