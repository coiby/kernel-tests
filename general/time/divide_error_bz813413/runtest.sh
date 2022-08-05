#!/bin/bash

. ../../../cki_lib/libcki.sh           || exit 1

TEST="general/time/divide_error_bz813413"

function runtest ()
{
    # guestfish command be included in libguestfs-tools-c package.
    yum -y install libguestfs-tools-c
    which guestfish
    if [ $? -ne 0 ]; then
        echo "no guestfish command, installation failed" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP"
        exit 0
    fi

    for i in `seq 1 100`; do
        guestfish -a /dev/null run -v > /tmp/fish.out 2>&1 ; 
        grep "divide error" /tmp/fish.out
        if [ $? -eq 0 ]; then
            echo "divide error in /tmp/fish.out, happens for ${i}th time" | tee -a $OUTPUTFILE
            rstrnt-report-log -l /tmp/fish.out
            rstrnt-report-result $TEST "FAIL" 1
        else
            echo "PASS: Ran 100 times guestfish, NO divide error found" | tee -a $OUTPUTFILE
            rstrnt-report-result $TEST "PASS" 0
        fi
    done
}

# ---------- Start Test -------------
# Setup some variables
runtest
exit 0
