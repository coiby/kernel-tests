#!/bin/bash

: ${OUTPUTFILE:=runtest.log}
: "${TEST:=general/time/multi_thread_clock_gettime}"

# ---------- Start Test -------------
cpu_num=$(cat /proc/cpuinfo | grep processor | wc -l)
gcc -o multi-thread-clock_gettime multi-thread-clock_gettime.c -pthread -lrt

service ntpd stop >& /dev/null
[ -e /usr/bin/systemctl ] && /usr/bin/systemctl stop chronyd >& /dev/null

./multi-thread-clock_gettime $cpu_num 2>&1 | tee -a $OUTPUTFILE &

sleep 3600

killall multi-thread-clock_gettime || true

service ntpd start >& /dev/null
[ -e /usr/bin/systemctl ] && /usr/bin/systemctl start chronyd >& /dev/null

./multi-thread-clock_gettime $cpu_num 2>&1 | tee -a $OUTPUTFILE &

sleep 3600

killall multi-thread-clock_gettime || true

cat $OUTPUTFILE

if grep -q 'FAIL:' $OUTPUTFILE; then
    echo "Time test Failed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result "$TEST" FAIL 1
else
    echo "Time test Passed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result "$TEST" PASS 0
fi

exit 0
