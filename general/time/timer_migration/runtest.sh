#!/bin/bash

. ../../../cki_lib/libcki.sh || exit 1

TEST="general/time/timer_migration"
RESULT="PASS"

function runtest()
{
    ORI_VAL=$(cat /proc/sys/kernel/timer_migration)
    echo "original value is $ORI_VAL" | tee -a $OUTPUTFILE
    # try to write -1, 2 to timer_migration. Only 0 and 1 is valid.
    for i in -1, 2; do
        echo $i > /proc/sys/kernel/timer_migration 2>&1
        if [ $? -eq 1 ]; then
            echo "$i is expected value, detected." | tee -a $OUTPUTFILE
        else
            RESULT="FAIL"
        fi
    done

    if [ $RESULT = "FAIL" ]; then
        echo "The Invalid argument vaule write to timer_migration"
        rstrnt-report-result $TEST $RESULT 1
    fi

    echo 0 > /proc/sys/kernel/timer_migration
    echo "recover timer_migration vaule" | tee -a $OUTPUTFILE
    echo $ORI_VAL > /proc/sys/kernel/timer_migration
    CUR_VAL=$(cat /proc/sys/kernel/timer_migration)
    if [ $ORI_VAL = $CUR_VAL ]; then
        echo "recover to original value, test pass."
        rstrnt-report-result $TEST $RESULT 0
    else
        echo "can't recover to original value, test fail."
        rstrnt-report-result $TEST $RESULT 1
    fi
}

runtest
exit 0
