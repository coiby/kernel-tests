#!/bin/bash

TEST="general/time/regression/bz862758_utime_stall"

runtest()
{
    gcc utime_hogs.c -o utime_hogs -lrt -lpthread
    eval "./utime_hogs 60 &" > utime_hogs.log
    sleep 3600
    pkill utime_hogs
    grep -i "ERROR" utime_hogs.log && {
        rstrnt-report-log -l utime_hogs.log
        rstrnt-report-result "${TEST}" "FAIL" 1
        exit 1
    }
    rstrnt-report-log -l utime_hogs.log
    rstrnt-report-result "${TEST}" "PASS" 0
}

echo "- Start utime/stime multiplication overflow problem" | tee -a $OUTPUTFILE
runtest
exit 0
