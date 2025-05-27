#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# source the rt library
. ../../include/lib.sh || exit 1

export TEST=rt-tests/printk/oom_deadlock

OOM_STRESSOR=${OOM_STRESSOR:-1024}
OOM_MEM=${OOM_MEM:-512000}  # 500MB
RUN_TIME=${RUN_TIME:-1h}
CGROUP_ROOT=/sys/fs/cgroup/rt-tests-printk-oom-deadlock


function delete_cgroups()
{
    phase_start_test "delete cgroups"
    local pids="$(find $CGROUP_ROOT -name cgroup.procs -exec cat {} \;)"
    # replace '\n' with space to prevent additional pids evaled as commands
    pids=${pids//$'\n'/ }
    if [[ -n "$pids" ]]; then
        log "remaining pids: $pids"
        run "ps -p ${pids//[[:space:]]/,} -o pid,ppid,cmd,%mem,%cpu"
        run "kill -9 $pids"
        # give the oom processes some time to exit
        run "sleep 10s"
    else
        log "no residual oom processes are left"
    fi

    run "find $CGROUP_ROOT -mindepth 1 -type d -exec rmdir {} +"
    run "rmdir $CGROUP_ROOT"
    phase_end
}

function create_cgroups()
{
    phase_start_test "create cgroups"
    run "mkdir -p $CGROUP_ROOT"
    run "echo '+memory' > $CGROUP_ROOT/cgroup.subtree_control"

    for i in $(seq "$OOM_STRESSOR"); do
        local group="$CGROUP_ROOT/stressor_${i}"
        run "mkdir -p $group"
        run "echo $OOM_MEM > $group/memory.max"
        run "echo 1 > $group/memory.oom.group"
    done
    phase_end
}

function oom_start()
{
    log "starting $OOM_STRESSOR stressors..."
    for i in $(seq "$OOM_STRESSOR"); do
        (
            while true; do
                (
                    run "echo $BASHPID > $CGROUP_ROOT/stressor_${i}/cgroup.procs"
                    # do not wrap the oom in a run command, otherwise the oom
                    # pid won't be the same with $BASHPID because run is
                    # executed at the expense of more processes
                    exec ./oom
                )
            done
        ) &
        run "echo $! >> killme_pids"
    done
    log "all oom stressors started!"
}

function console_spammer()
{
    log "starting the console spammer..."
    (
        while true; do
            echo "lllllllllllllllllllllllllllllllllllllllllllooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooonnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnngggggggggggggggggggggggggggg" > /dev/console
            sleep 0.25
        done
    ) &
    run "echo $! >> killme_pids"
    log "the console spammer started!"
}

function cleanup()
{
    phase_start_cleanup
    local pids=$(cat killme_pids)
    pids=${pids//$'\n'/ }
    run "kill -9 $pids"
    run "mv killme_pids killme_pids.old"
    # run with -l because the oom processes may already be killed by oom-killer
    run -l "killall oom"
    run "sleep 10s"
    phase_end
}

function main()
{
    oneliner "gcc oom.c -o oom"
    [[ -x oom ]] || return 1

    if [[ -d $CGROUP_ROOT ]]; then
        delete_cgroups
        return 1
    else
        create_cgroups
        # trap cleanup EXIT
        phase_start_test "oom deadlock"
        console_spammer
        oom_start
        run "sleep $RUN_TIME"
        # if the test can reach this echo then system didn't lockup
        run "echo pass"
        phase_end
        cleanup
        delete_cgroups
        return 0
    fi
}

main
