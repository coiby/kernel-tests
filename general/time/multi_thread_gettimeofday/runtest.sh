#!/bin/bash

TEST="general/time/multi_thread_gettimeofday"
: ${OUTPUTFILE:=runtest.log}

# ---------- Start Test -------------
cpu_num=$(cat /proc/cpuinfo | grep processor | wc -l)

gcc -o multi-thread-gettimeofday multi-thread-gettimeofday.c -pthread

systemctl stop chronyd || service ntpd stop

./multi-thread-gettimeofday $cpu_num 2>&1 | tee -a $OUTPUTFILE &
sleep 600
killall multi-thread-gettimeofday

systemctl start chronyd || service ntpd start

./multi-thread-gettimeofday $cpu_num 2>&1 | tee -a $OUTPUTFILE &
sleep 600
killall multi-thread-gettimeofday

if grep -q 'Failed:' $OUTPUTFILE; then
    echo "Time test Failed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "FAIL" 1
else
    echo "Time test Passed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "PASS" 0
fi

exit 0
