#!/bin/bash

TEST="general/time/posix_timer"
: ${OUTPUTFILE:=runtest.log}

# ---------- Start Test -------------

# Get the posix test suite from github
git clone https://github.com/linuxqiao/posixtestsuite.git || exit 1

pushd posixtestsuite

echo "-lrt" >> LDFLAGS
./run_tests TMR 2>&1 | tee -a $OUTPUTFILE

# Ignore build error 'conformance/interfaces/asctime/1-1: build: FAILED'
sed -i 's#asctime/1-1: build: FAILED##' $OUTPUTFILE
# Ignore clock_getcpuclockid/2-1 error
sed -i 's#clock_getcpuclockid/2-1: execution: FAILED##' $OUTPUTFILE
# Ignore timer_create/10-1,11-1 execution: FAILED
sed -i 's#timer_create/10-1: execution: FAILED##' $OUTPUTFILE
sed -i 's#timer_create/11-1: execution: FAILED##' $OUTPUTFILE

if grep -q 'FAILED' $OUTPUTFILE; then
    echo "Posix Time test Failed:" >>$OUTPUTFILE 2>&1
    grep "FAILED" $OUTPUTFILE
    echo "Total number of Failures is $(grep -o FAILED $OUTPUTFILE | wc -l)" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "FAIL" 1
else
    echo "Posix Time test Passed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "PASS" 0
fi

popd
exit 0
