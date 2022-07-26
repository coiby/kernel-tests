#! /bin/bash -x

. ../../../cki_lib/libcki.sh || exit 1

TEST="general/time/clock_gettime"
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

function runtest ()
{
    day_now=`date +%d`
    hour_now=`date +%H`
    minute_now=`date +%M`
    sec_now=`date +%S`

    echo "***** Start gtod_backwards *****" | tee -a $OUTPUTFILE
    J=0
    while [ $J -lt 1000 ]; do
        J=`expr $J + 1`
        echo "***** loop number $J *****" | tee -a $OUTPUTFILE
        ./gtod_backwards 2>&1 | tee -a $OUTPUTFILE
    done

    if [ $day_now = `date +%d` ]; then
        if [ $hour_now = `date +%H` ]; then
            time_temp=`date +%M`
            run_time=`expr "$time_temp" - "$minute_now" `
            echo "running for $run_time minutes" | tee -a $OUTPUTFILE
        else
            time_temp_H=`date +%H`
            time_temp_M=`date +%M`
            temp_hour=`expr "$time_temp_H" - "$hour_now"`
            run_time=`expr $(( $temp_hour * 60 )) + $time_temp_M - $minute_now`
            echo "running for $run_time minutes" | tee -a $OUTPUTFILE
        fi
    else
        time_temp_D=`date +%d`
        time_temp_H=`date +%H`
        temp_day=`expr "$time_temp_D" - "$day_now"`
        run_time=`expr $(( $temp_day * 24 )) + $time_temp_H - $hour_now`
        run_time=$(($run_time * 60))
        echo "runnging about $run_time minutes" | tee -a $OUTPUTFILE
    fi

    if [ $run_time -gt 480 ]; then
        echo "WARN : the performance of this machine is too low ......" | tee -a $OUTPUTFILE
    fi
}

# ---------- Start Test -------------

gcc -o gtod_backwards gtod_backwards.c -lrt
if [ $? -ne 0 ]; then
    echo "gtod_backwards.c compilation fails!"
    rstrnt-report-result $TEST SKIP
    exit 0
fi

if [ $rhel_major -lt 8 ]; then
    service ntpd stop >& /dev/null
    runtest
    service ntpd start >& /dev/null
else
    systemctl stop chronyd >& /dev/null
    runtest
    systemctl start chronyd >& /dev/null
fi

if grep -q 'Failed:' $OUTPUTFILE; then
    echo "Time test Failed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "FAIL" 1
else
    echo "Time test Passed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "PASS" 0
fi

exit 0
