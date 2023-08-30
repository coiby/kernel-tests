#!/bin/bash

TEST="general/time/usleep_range_bz786458"

function result_fail()
{
    echo "***** End of runtest.sh *****" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST FAIL 1
}

function result_pass ()
{
    echo "***** End of runtest.sh *****" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST PASS 0
}

function runtest ()
{
    # start
    echo "start testing ..." | tee -a $OUTPUTFILE

    unset ARCH
    make -C ./usleep_range/
    [ $? != 0 ] && result_fail
    export ARCH=$(uname -m)

    insmod ./usleep_range/usleep_range.ko
    sleep 2
    rmmod ./usleep_range/usleep_range.ko

    printf "\nlog:\n"
    grep -B3 'Sleeping' /var/log/messages | awk -F: '{print $4}' | tee -a $OUTPUTFILE
    grep "Sleeping for" /var/log/messages > /tmp/TEMP.file
    printf "\n"
    rstrnt-report-log -l "/tmp/TEMP.file"

    count=0
    while read line
    do
        ((count++))
        USEC=`echo "$line" | cut -d '>' -f 2 | tr -d '[a-z A-Z]'`

        if [ $count -eq 1 ];then
            echo "Checking usleep_range()" | tee -a $OUTPUTFILE

            if [ $USEC -gt 1000 -o $USEC -lt 2000 ];then
                printf "\t=> check ok.\n" | tee -a $OUTPUTFILE
            else
                echo "Failed: usleep_range() checking failed." | tee -a $OUTPUTFILE
                result_fail
            fi
        else
            echo "Checking msleep()" | tee -a $OUTPUTFILE

            if [ $USEC -lt 1000 ];then
                echo "Failed: msleep() checking failed." | tee -a $OUTPUTFILE
                result_fail
            else
                printf "\t=> check ok.\n" | tee -a $OUTPUTFILE
                echo "PASS." | tee -a $OUTPUTFILE
                result_pass
            fi
        fi
    done < /tmp/TEMP.file
}

# ---------- Start Test -------------
[[ ! $(uname -m) =~ "86" ]] && echo "The current architecture is $(uname -m), this cast just support x86 architecture!" && result_pass
runtest
exit 0
