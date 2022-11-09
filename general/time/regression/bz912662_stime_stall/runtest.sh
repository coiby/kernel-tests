#!/bin/bash

TEST="general/time/regression/bz912662_stime_stall"

runtest()
{
    gcc stime_hogs.c -o stime_hogs -lrt -lpthread
    eval "./stime_hogs 60 &" > stime_hogs.log  # crate 60 threads
    sleep 3600 # sleep 1 hour to detect
    pkill stime_hogs
    grep -i "ERROR" stime_hogs.log && {
        rstrnt-report-log -l stime_hogs.log
        rstrnt-report-result "${TEST}" "FAIL" 1
        exit 1
    }
    rstrnt-report-log -l stime_hogs.log
    rstrnt-report-result "${TEST}" "PASS" 0
}

echo "- Start utime/stime multiplication overflow problem" | tee -a $OUTPUTFILE
runtest
exit 0
