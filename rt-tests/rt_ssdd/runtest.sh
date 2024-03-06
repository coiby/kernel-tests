#!/bin/bash

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh
: ${OUTPUTFILE:=runtest.log}

# Source rt common functions
. ../include/runtest.sh || exit 1

export TEST="rt-tests/rt_ssdd"

if ! kernel_automotive; then
    declare pkg_name="rt-tests" && (( rhel_x >= 9 )) && pkg_name="realtime-tests"
    which ssdd || yum install -y $pkg_name
fi

NFORKS=${NFORKS:=10}
NITERS=${NITERS:=10000}

echo "Runing ssdd $NFORKS $NITERS [default]" | tee -a $OUTPUTFILE
ssdd --forks=$NFORKS --iters=$NITERS | tee SSDD1.LOG
rstrnt-report-log -l SSDD1.LOG
if grep -q "All tests PASSED" SSDD1.LOG; then
    rstrnt-report-result $TEST "PASS" "0"
else
    rstrnt-report-result $TEST "FAIL" "1"
fi

NFORKS=100
NITERS=10000
echo "Running ssdd $NFORKS $NITERS [stress]" | tee -a $OUTPUTFILE
ssdd --forks=$NFORKS --iters=$NITERS | tee SSDD2.LOG
rstrnt-report-log -l SSDD2.LOG
if grep -q "All tests PASSED" SSDD2.LOG; then
    rstrnt-report-result "ssdd stress" "PASS" "0"
else
    rstrnt-report-result "ssdd stress" "FAIL" "1"
fi

exit 0
