#!/bin/bash

export TEST="rt-tests/us/rtla/rtla-hwnoise"
export result_r="PASS"
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')
export rhel_minor=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $2}')

function check_status()
{
    if [ $? -eq 0 ]; then
        echo ":: $* :: PASS ::" | tee -a $OUTPUTFILE
    else
        result_r="FAIL"
        echo ":: $* :: FAIL ::" | tee -a $OUTPUTFILE
    fi
}

function runtest()
{
    # rtla supports from 8.8 and 9.2
    if ! ( (( "$rhel_major" == 8 && "$rhel_minor" >= 8 )) || (( "$rhel_major" == 9 && "$rhel_minor" >=2 )) || (( "$rhel_major" >= 10 ))); then
        echo "rtla is only supported for RHEL >= 8.8 and >= 9.2" || tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" 0
        exit 0
    fi

    echo "Package rtla-hwnoise sanity test:" | tee -a $OUTPUTFILE
    rpm -q --quiet rtla || yum install -y rtla || {
        echo "Install rtla failed" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "WARN" 0
        exit 1
    }

    echo "-- rtla-hwnoise: verify help page -------------------" | tee -a $OUTPUTFILE
    rtla hwnoise --help
    check_status "rtla hwnoise --help"

    echo "-- rtla-hwnoise: detect noise higher than one microsecond -------------------" | tee -a $OUTPUTFILE
    rtla hwnoise -c 0 -T 1 -d 5s -q
    check_status "rtla hwnoise -c 0 -T 1 -d 5s -q"

    echo "-- rtla-hwnoise: set the automatic trace mode -------------------" | tee -a $OUTPUTFILE
    rtla hwnoise -a 5
    check_status "rtla hwnoise -a 5"

    echo "-- rtla-hwnoise: set scheduling param to the osnoise tracer threads -------------------" | tee -a $OUTPUTFILE
    rtla hwnoise -P F:1 -c 0 -r 900000 -d 1M -q
    check_status "rtla hwnoise -P F:1 -c 0 -r 900000 -d 1M -q"

    echo "-- rtla-hwnoise: stop the trace if a single sample is higher than 1 us -------------------" | tee -a $OUTPUTFILE
    rtla hwnoise -s 1 -T 1 -t
    check_status "rtla hwnoise -s 1 -T 1 -t"

    echo "-- rtla-hwnoise: stop the trace if a total sample is higher than 1 us -------------------" | tee -a $OUTPUTFILE
    rtla hwnoise -S 1 -T 1 -t -D
    check_status "rtla hwnoise -S 1 -T 10 -t -D"

    echo "-- rtla-hwnoise: enable a trace event trigger -------------------" | tee -a $OUTPUTFILE
    rtla hwnoise -t -e osnoise:irq_noise --trigger="hist:key=desc,duration/1000:sort=desc,duration/1000:vals=hitcount" -d 1m
    check_status "rtla hwnoise -t -e osnoise:irq_noise --trigger="hist:key=desc,duration/1000:sort=desc,duration/1000:vals=hitcount" -d 1m"

    if [ $result_r = "PASS" ]; then
        echo "Overall result: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall result: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

runtest
exit 0
