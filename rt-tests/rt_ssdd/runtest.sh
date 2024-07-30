#!/bin/bash

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh

# Source rt common functions
. ../include/lib.sh || exit 1

export rhel_x

if ! kernel_automotive; then
    declare pkg_name="rt-tests" && (( rhel_x >= 9 )) && pkg_name="realtime-tests"
    which ssdd || yum install -y $pkg_name
fi

NFORKS=${NFORKS:=10}
NITERS=${NITERS:=10000}

phase_start_test "Runing ssdd $NFORKS $NITERS [default]"
run "ssdd --forks=$NFORKS --iters=$NITERS | tee SSDD1.LOG"
rstrnt-report-log -l SSDD1.LOG
if grep -q "All tests PASSED" SSDD1.LOG; then
    log_pass "ssdd default PASS"
else
    log_fail "ssdd default FAIL"
fi
phase_end

NFORKS=100
NITERS=10000
phase_start_test "Running ssdd $NFORKS $NITERS [stress]"
run "ssdd --forks=$NFORKS --iters=$NITERS | tee SSDD2.LOG"
rstrnt-report-log -l SSDD2.LOG
if grep -q "All tests PASSED" SSDD2.LOG; then
    log_pass "ssdd stress PASS"
else
    log_fail "ssdd stress FAIL"
fi
phase_end

exit 0
