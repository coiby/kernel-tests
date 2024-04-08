#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

export TEST="rt-tests/us/tuna/sanity"
export result_r="PASS"

function check_status()
{
    if [ $? -eq 0 ]; then
        echo ":: $* :: PASS ::" | tee -a $OUTPUTFILE
    else
        result_r="FAIL"
        echo ":: $* :: FAIL ::" | tee -a $OUTPUTFILE
    fi
}

function tuna_rhel()
{
    echo "Reviewing the system in the CLI:" | tee -a $OUTPUTFILE
    tuna show_threads
    check_status "tuna show_threads"
    tuna show_irqs
    check_status "tuna show_irqs"

    echo "CPU tuning in the CLI:" | tee -a $OUTPUTFILE
    tuna run "ps all" --cpus=0,1
    check_status "tuna run='ps all' --cpus=0,1"

    echo "Task tuning in the CLI:" | tee -a $OUTPUTFILE
    tuna show_threads --threads=1
    check_status "tuna show_threads --threads=1"
}

function tuna_rhel8()
{
    echo "Reviewing the system in the CLI:" | tee -a $OUTPUTFILE
    tuna --show_threads
    check_status "tuna --show_threads"
    tuna --show_irqs
    check_status "tuna --show_irqs"

    echo "CPU tuning in the CLI:" | tee -a $OUTPUTFILE
    tuna --cpus=0,1 --run="ps all"
    check_status "tuna --cpus=0,1 --run='ps all'"

    echo "Task tuning in the CLI:" | tee -a $OUTPUTFILE
    tuna --threads=1 --show_threads
    check_status "tuna --threads=1 --show_threads"
}

function runtest()
{
    echo "Package tuna sanity test:" | tee -a $OUTPUTFILE
    rpm -q --quiet tuna || yum install -y tuna
    check_status "install tuna"

    # since 9.2 tuna CLI feature changes, detail in bz2062865
    if rhel_in_range 0 9.1; then
        tuna_rhel8
    else
        tuna_rhel
    fi

    if [ $result_r = "PASS" ]; then
        echo "Overall results: PASS" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "PASS" 0
    else
        echo "Overall results: FAIL" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "FAIL" 1
    fi
}

runtest
exit 0
