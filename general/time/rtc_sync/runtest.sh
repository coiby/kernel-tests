#!/bin/bash

TEST="general/time/rtc_sync"

# detail see bz1793880

function runtest()
{
    # keep rtcsync in /etc/chrony.conf (that is the default)
    grep "rtcsync" /etc/chrony.conf || {
        echo "Enable kernel synchronization of the real-time clock (RTC)"
        echo "#Enable kernel synchronization of the real-time clock (RTC)" >> /etc/chrony.conf
        echo "rtcsync" >> /etc/chrony.conf
        systemctl restart chronyd || {
            echo "restart chronyd service failed!"
            rstrnt-report-result $TEST FAIL 1
            exit 1
        }
    }

    # The waitsync command waits for chronyd to synchronise.
    # which will wait up to about 10 minutes (60 times 10 seconds) for chronyd to synchronise
    # check default by: man chronyc
    chronyc waitsync
    echo "set RTC time up 10 seconds"
    timedatectl
    hwclock --set --date '10 sec'
    timedatectl
    echo "wait 11 minutes and check again"
    sleep 11m
    timedatectl | tee time.log
    date1=$(cat time.log | grep "Local time" | head -n1 | awk -F' ' '{print $4" "$5}')
    date2=$(cat time.log | grep "RTC time" | head -n1 | awk -F' ' '{print $4" "$5}')
    local_time=$(date -d "$date1" +%s)
    rtc_time=$(date -d "$date2" +%s)

    res=$(expr $local_time - $rtc_time)
    if [ $res -lt 0 ]; then
        res=$(expr 0 - $res)
    fi

    if [ $res -gt 1 ]; then
        echo "RTC time should within <1 second of the Local time"
        rstrnt-report-result $TEST FAIL 1
        exit 1
    fi
    rstrnt-report-result $TEST PASS 0
}

if [ $(uname -m) == "x86_64" -o $(uname -m) == "aarch64" ]; then
    runtest
else
    echo "Not support $(uname -m) architecture"
    rstrnt-report-result $TEST "SKIP"
fi
exit 0
