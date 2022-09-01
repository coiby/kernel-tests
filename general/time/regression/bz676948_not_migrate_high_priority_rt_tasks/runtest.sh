#!/bin/bash

TEST="general/time/regression/bz676948_not_migrate_high_priority_rt_tasks"

function runtest()
{
    ALL_LOG_FILES='trace-cmd.log'
    echo "THIS TEST NEED TO BE RUN ON HOST MORE THAN ONE AND FEWER THAN 3 "\
        "ACTIVE CPUS"
    cpu_num=$(lscpu -p | grep -v '^#' | wc -l)
    gcc migrate.c -o migrate -lrt -lpthread
    # if [ $cpu_num -gt 3 -o $cpu_num -le 1 ]; then
    if [ $cpu_num -le 1 ]; then
        echo "Cpu number is $cpu_num, which is invalid"
        echo "You can use boot arg of maxcpus=n to adjust the cpu number"
        echo "SKIP and exiting!!!"
        rstrnt-report-result $TEST "SKIP" 0
    else
        rpm -q trace-cmd || yum install -y trace-cmd
        trace-cmd record -e 'sched_wakeup*' -e sched_switch \
            -e 'sched_migrate*' ./migrate | tee -a trace-cmd.log
        rstrnt-report-log -l trace-cmd.log
        rstrnt-report-result $TEST "PASS" 0
    fi
}

runtest
exit 0
