#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1
. ../../../kernel-include/runtest.sh || exit 1

TEST="general/time/gettimeofday"

devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
installer=$(K_GetPkgMgr)
if [[ ${installer} == "rpm-ostree" ]]; then
    export install_opts="-A -y --idempotent --allow-inactive install"
else
    export install_opts="-y install"
fi
${installer} ${install_opts} ${devel_pkg}

function runtest()
{
    # Disable timedifftest-qa test.  This is known failure in RHEL5.
    # Fix for this issue is significant and would require medium code
    # change - see BZs 250708 and 4611184.

    # get the time now
    day_now=`date +%d`
    hour_now=`date +%H`
    minute_now=`date +%M`
    sec_now=`date +%S`

    echo "***** Start timedrift *****" | tee -a $OUTPUTFILE
    ./timedrift 2>&1 | tee -a $OUTPUTFILE

    echo "***** Start gtod_backwards *****" | tee -a $OUTPUTFILE
    J=0
    while [ $J -lt 100 ]; do
        J=`expr $J + 1`
        echo "***** Start loop number $J *****" | tee -a $OUTPUTFILE
        ./gtod_backwards 2>&1 | tee -a $OUTPUTFILE
        echo "***** Done loop number $J *****" | tee -a $OUTPUTFILE
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
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

gcc -Wall -W -D_GNU_SOURCE -o timedrift timedrift.c
gcc -Wall -W -D_GNU_SOURCE -o gtod_backwards gtod_backwards.c
gcc -Wall -W -D_GNU_SOURCE -o timedifftest-qa timedifftest-qa.c

if [ $rhel_major -ge 8 ]; then
    systemctl stop chronyd
    runtest
    systemctl start chronyd
else
    service ntpd stop >& /dev/null
    runtest
    service ntpd start >& /dev/null
fi

if grep -q 'Failed:' $OUTPUTFILE; then
    echo "Time test Failed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "FAIL" 1
else
    echo "Time test Passed:" >>$OUTPUTFILE 2>&1
    rstrnt-report-result $TEST "PASS" 0
fi

exit 0
