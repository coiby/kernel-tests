#!/bin/bash

cgdir=$1
controllers="${2//,/ }"


if mount | grep -qE "^cgroup2"; then
        CGROUP_ROOT=$(mount | awk '/cgroup2/ {print $3; exit}')
        nr_v2_controllers=$(awk '{print NF}' "$CGROUP_ROOT/cgroup.controllers")
        if ((nr_v2_controllers > 0)); then
                CGROUP_VERSION=2
                CGROUP_TASK_FILE=cgroup.procs
        else
                CGROUP_VERSION=1
                CGROUP_ROOT=$(mount | grep cgroup | awk '/cgroup /{split($3, a, "cgroup"); print a[1]"cgroup"; exit}')
                CGROUP_TASK_FILE=tasks
        fi
else
        CGROUP_VERSION=1
        CGROUP_ROOT=$(mount | grep cgroup | awk '/cgroup /{split($3, a, "cgroup"); print a[1]"cgroup"; exit}')
        CGROUP_TASK_FILE=tasks
fi

function usage()
{
       echo -e "Usage:\n  $0 <cgroup_dir> <controller[,controller]...> <command to run>"
       echo -e "  Note: Need to use same cgroup dir name for all controllers in cgroup v1"
       echo -e "E.G:\n  $0 test cpu,memory sleep 120 &"
           exit
}

function fix_cgroup_dir()
{
        local dir=$1
        local controller=$2

        if [ "$CGROUP_VERSION" = 1 ]; then
                local fixed_controller_dir=$(mount -t cgroup | awk '/'"$controller"',|'"$controller"' / {print $3; exit}')
                local tgt_dir=$fixed_controller_dir/$dir/
        elif [ "$CGROUP_VERSION" = 2 ]; then
                local tgt_dir=$CGROUP_ROOT/$dir/
        fi

        shopt -s extglob
        tgt_dir=${tgt_dir%%+(/)}
        shopt -u extglob

        echo "$tgt_dir"
}

[ $# -lt 2 ] && usage


if [ "$CGROUP_VERSION" = 1 ]; then
        for controller in $controllers; do
                tgt_dir=$(fix_cgroup_dir $cgdir $controller)
                test -d "$tgt_dir"
                [ $? -ne 0 ] && echo "No cgroup exist: $tgt_dir !" && exit 1
                echo $$ >> "$tgt_dir/$CGROUP_TASK_FILE"
                [ $? -ne 0 ] && echo "$0: failed to migrate to cgroup" && exit 1
        done
else
        tgt_dir=$(fix_cgroup_dir "$cgdir" "$controllers")
        echo $$ >> "$tgt_dir/$CGROUP_TASK_FILE"
fi

shift 2
exec "$*"
