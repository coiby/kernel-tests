#!/bin/bash
: ${OUTPUTFILE:=runtest.log}

# Include beaker environment
. /usr/bin/rhts_environment.sh || exit 1

# Source rt common functions
. ../../../include/lib.sh || exit 1

# Vars
export TEST="rt-tests/us/stalld/selftest"

function install_and_start_stalld()
{
    # Only run on 8.4 and up
    if rhel_in_range 0 8.3; then
        echo "stalld is only supported for RHEL >= 8.4 and up" || tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" 5
        exit 0
    fi

    # Verify stalld is installed
    rpm -q stalld || yum install -y stalld || {
        echo "Could not install stalld" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 5
        exit 1
    }

    # Enable stalld if needed
    systemctl status stalld.service >>$OUTPUTFILE 2>&1 || {
        echo "Starting stalld" | tee -a $OUTPUTFILE
        systemctl start stalld.service || {
            echo "Stalld failed to start" | tee -a $OUTPUTFILE
            rstrnt-report-result $TEST "FAIL" 5
            exit 1
        }
    }
}

function run_test ()
{
    echo "Test Start Time: $(date)" | tee -a $OUTPUTFILE
    selftest=0

    echo "Compile selftest" | tee -a $OUTPUTFILE
    gcc -g -Wall -pthread -o selftest selftest.c -lpthread
    if [ $? -ne 0 ]; then
        echo "compile selftest binary FAIL." | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 5
        return
    fi

    echo "Running selftest" | tee -a $OUTPUTFILE
    ./selftest -d | tee -a $OUTPUTFILE
    selftest=${PIPESTATUS[0]}

    if [ "$selftest" -eq 0 ]; then
        echo "selftest PASS." | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "selftest FAIL." | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi

    echo "Test End Time: $(date)" | tee -a $OUTPUTFILE
}

function stop_stalld()
{
    echo "Stoping stalld." | tee -a $OUTPUTFILE
    systemctl stop stalld.service || {
        echo "Stalld failed to stop." | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 5
        exit 1
    }
}

# ---------- Start Test -------------

install_and_start_stalld
run_test
stop_stalld
exit 0
