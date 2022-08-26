#!/bin/bash

TEST="general/time/regression/bz1064059_clock_nanosleep_return_early"

echo "=== Start Here ==="
count=10000
gcc -o tst-cpuclock2 -std=gnu99 tst-cpuclock2.c -g -pthread -lrt -Wall

while :
do
    ./tst-cpuclock2 | tee -a $OUTPUTFILE
    ((count--))
    [ $count -lt 0 ] && break
done

if grep -q 'clock_nanosleep' $OUTPUTFILE; then
    echo "Have clock_nanosleep error, test failed"
    rstrnt-report-result $TEST "FAIL" 1
else
    echo "No clock_nanosleep error, test passed"
    rstrnt-report-result $TEST "PASS" 0
fi
exit 0
