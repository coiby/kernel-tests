#!/bin/bash

TEST="general/time/posix_timer"
: ${OUTPUTFILE:=runtest.log}

# ---------- Start Test -------------

wget http://download.eng.bos.redhat.com/qa/rhts/lookaside/posixtestsuite-1.5.0.tar.gz
tar zxf posixtestsuite-1.5.0.tar.gz

pushd posixtestsuite
echo "-lrt" >> LDFLAGS
./run_tests TMR 2>&1 | tee -a $OUTPUTFILE

# Ignore build error 'conformance/interfaces/asctime/1-1: build: FAILED'
sed -i /"build: FAILED"/d $OUTPUTFILE

if grep -q 'FAILED' $OUTPUTFILE; then
    echo "Posix Time test Failed:" >>$OUTPUTFILE 2>&1
    echo "Total number of Failures is $(grep -o FAILED $OUTPUTFILE | wc -l)" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "FAIL" 1
else
    echo "Posix Time test Passed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "PASS" 0
fi

popd
exit 0
