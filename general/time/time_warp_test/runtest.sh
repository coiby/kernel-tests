#!/bin/bash

TEST="general/time/time_warp_test"

function test_fail()
{
    echo "FAIL: $*"
    rstrnt-report-result $TEST "FAIL" 1
}

function test_pass()
{
    echo "PASS: $*"
    rstrnt-report-result $TEST "PASS" 0
}

gcc -Wall -O2 -o time-warp-test time-warp-test.c -lrt || {
    echo "Compile time-warp-test failed!"
    rstrnt-report-result $TEST "SKIP"
    exit 0
}
./time-warp-test &
sleep 3600 # sleep 1 hour to trigger the warp issue
killall time-warp-test

rstrnt-report-log -l output.txt

if grep -q 'TSC-warp' output.txt; then
    echo "Test Failed(TSC-warp):" >> $OUTPUTFILE 2>&1
    test_fail
elif grep -q 'TOD-warp' output.txt; then
    echo "Test Failed(TOD-war):" >> $OUTPUTFILE 2>&1
    test_fail
elif grep -q 'CLOCK-warp' output.txt; then
    echo "Test Failed(CLOCK-warp):" >> $OUTPUTFILE 2>&1
    test_fail
else
    echo "Test Passed:" >> $OUTPUTFILE 2>&1
    test_pass
fi

exit 0
