#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/getboottime"
SLEEP_TIME=10
FAIL=0
BOOTTIME_FAIL=0

function checkboottime ()
{
    COUNT=1024
    BOOTTIME_1=`cat /proc/stat | grep "btime" | awk '{print $2}'`

    while [ $COUNT -ge 0 ]; do
        BOOTTIME_2=`cat /proc/stat | grep "btime" | awk '{print $2}'`
        if [[ $BOOTTIME_1 != $BOOTTIME_2 ]]; then
            printf "FAIL: boottime not stable count = $COUNT\n\t * Before boottime = $BOOTTIME_1\n\t * After boottime = $BOOTTIME_2\n" | tee -a $OUTPUTFILE
            return 1
        fi

        ((COUNT--))
    done

    return 0
}

function runtest ()
{
    #ntpdate clock.redhat.com > /dev/null 2>&1

    echo "First Round check the boottime" | tee -a $OUTPUTFILE
    checkboottime
    RES=$?
    if [ $RES -ne 0 ]; then
        echo "## First Round test Failed" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
        exit 1
    fi
    echo "First Round ... done" | tee -a $OUTPUTFILE

    START_TIME=`./time | sed -n 2p | awk '{ print $1 }'`
    echo "** Testing start time : $START_TIME seconds" | tee -a $OUTPUTFILE
    # testing start
    i=0
    while [ $i -lt 360 ]; do
        BOOTTIME_1=`cat /proc/stat | grep "btime" | awk '{print $2}'`
        # setting time forward 1 second
        ./settimeofday
        BOOTTIME_2=`cat /proc/stat | grep "btime" | awk '{print $2}'`
        DELTA=`expr $BOOTTIME_2 - $BOOTTIME_1`

        if [[ $DELTA != 1 ]]; then
            echo "!! FAIL : boottime testing failed" | tee -a $OUTPUTFILE
            printf "\t boottime1 = $BOOTTIME_1 \n\t boottime2 = $BOOTTIME_2 \n" | tee -a $OUTPUTFILE
            rstrnt-report-result $TEST "FAIL" 1
            exit 1
        fi

        ((i++))
    done

    END_TIME=`./time | sed -n 2p | awk '{ print $1 }'`
    RUN_TIME=`expr $END_TIME - $START_TIME`
    echo "** Testing done  time : $END_TIME seconds " | tee -a $OUTPUTFILE
    echo "   Time elapsed for $RUN_TIME seconds"

    checkboottime
    RES=$?
    if [ $RES -ne 0 ]; then
        echo "## Second Round test Failed" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
        exit 1
    fi

    echo ">> Testing PASS" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST "PASS" 0
}

# ---------- Start Test -------------
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

gcc -o settimeofday settimeofday.c
gcc -o time time.c

if (type systemctl); then
    systemctl stop chronyd
    runtest
    systemctl start chronyd 
else
    service ntpd stop > /dev/null 2>&1
    runtest 
    service ntpd start > /dev/null 2>&1
fi

exit 0
