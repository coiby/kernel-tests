#!/bin/bash

. ../../../../kernel-include/runtest.sh || exit 1

pmgr=$(K_GetPkgMgr)

if [ ${pmgr} == "rpm-ostree" ]; then
    install_opts="-A --idempotent --allow-inactive install -y"
else
    install_opts="install -y"
fi

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
        rpm -q trace-cmd || ${pmgr} ${install_opts} trace-cmd || exit 1
        trace-cmd record -e 'sched_wakeup*' -e sched_switch \
            -e 'sched_migrate*' ./migrate | tee -a trace-cmd.log
        rstrnt-report-log -l trace-cmd.log
        rstrnt-report-result $TEST "PASS" 0
    fi
}

runtest
exit 0
