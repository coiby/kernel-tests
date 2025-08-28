#!/bin/bash
# shellcheck disable=SC1083,SC2320
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/include
#   Description: schedule test common lib
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../../cki_lib/libcki.sh || exit 1

. /usr/share/beakerlib/beakerlib.sh || exit 1

SCHED_PROCESS_SRC=../include/processes
SCHED_PROCESS_BIN=$(pwd)/tasks
export SCHED_NR_CPU=$(grep -wo processor /proc/cpuinfo | wc -l)

# Copy from zswap test
function stress_install()
{
        if [ ! -f stress-1.0.4.tar.gz ]; then
                wget http://download.eng.rdu2.redhat.com/qa/rhts/lookaside/stress-1.0.4.tar.gz;
        fi
        if ! which stress; then
                tar xzf stress-1.0.4.tar.gz >/dev/null 2>&1
                pushd stress-1.0.4; ./configure >/dev/null 2>&1 ; make >/dev/null 2>&1 && make install >/dev/null 2>&1;  popd
        fi
        export SCHED_STRESS_PATH=$(dirname $(which stress))
}

# Use stress package to do hog operation on io/vm/cpu
function _wget_compile_stress()
{
        local TGT_MD5=2fa99c658db4d7d7adc9748bf2b463cd
        local S_NVR=stress-0.18.8-1.4.el7.src.rpm
        local STRESS_SRPM=http://download.devel.redhat.com/brewroot/packages/stress/0.18.8/1.4.el7/src/stress-0.18.8-1.4.el7.src.rpm

        [ -f $S_NVR ] && RL_MD5=$(md5sum $S_NVR | awk '{print $1}')
        # We have gotten the package and md5 is right, return directly.
        [ -n "$RL_MD5" ] && echo $RL_MD5 | grep $TGT_MD5 && local SKIP_DOWNLOAD=1

        export SCHED_STRESS_PATH=/root/rpmbuild/BUILD/stress-0.18.8/src
        if which stress || test -f $SCHED_STRESS_PATH/stress; then
                return 0
        fi

        if [ ! "$SKIP_DOWNLOAD" = 1 ]; then
                wget $STRESS_SRPM || { rstrnt-report-result "wget_stress" FAIL; rlDie "wget stress"; }
        fi
        rpm -ivh stress-0.18.8-1.4.el7.src.rpm
        rpm -q yum-utils || yum -y install yum-utils
        which rpmbuild || yum -y install rpm-build &>/dev/null
        yum-builddep -y /root/rpmbuild/SPECS/stress.spec

        # for rhel8, use the tar ball, as srpm can't compile successfully for unkown reason.
        if ! grep 'release 7' /etc/redhat-release; then
                stress_install
        else
                rpmbuild -bi /root/rpmbuild/SPECS/stress.spec
        fi
        if [ ! -f $SCHED_STRESS_PATH/stress ]; then
                rstrnt-report-result "compile_stress" FAIL
                return
        fi
        rstrnt-report-result "compile_stress" PASS
}

function source_compile()
{
        _wget_compile_stress
        if [ ! -d tasks ]; then
                mkdir tasks
        fi
        gcc $SCHED_PROCESS_SRC/cpu_hog.c -lrt -o $SCHED_PROCESS_BIN/cpu_hog
        gcc $SCHED_PROCESS_SRC/life.c -lrt -o $SCHED_PROCESS_BIN/life
}

#--------------------------------------------------
# For scheduler load average statistict operation
function load_avg_sum()
{
        local logfile=$1
        cat /proc/loadavg | tee -a $logfile
        local avg_1_5_15=$(cat /proc/loadavg| awk '{printf("%s-%s-%s\n", $1,$2,$3)}')
        local avg_1=$(echo $avg_1_5_15 | awk '{print $1}')
        local avg_5=$(echo $avg_1_5_15 | awk '{print $2}')
        local avg_15=$(echo $avg_1_5_15 | awk '{print $3}')

        echo $avg_1 > avg_1_$(uname -r)
        echo $avg_5 > avg_5_$(uname -r)
        echo $avg_15 > avg_15_$(uname -r)

        local nr_cpus=$(nproc)
        rstrnt-report-result "cpu${nr_cpus}:loadavg:$avg_1_5_15"
}

function print_system_info()
{
        set -x
        local logfile=$1
        vmstat | tee -a $logfile
        echo | tee -a $logfile
        lscpu | tee -a $logfile

        echo | tee -a $logfile
        echo "free -m" | tee -a $logfile
        free -m | tee -a $logfile

        echo sched_debug | tee -a $logfile
        if [ -f /proc/sched_debug ]; then
                cat /proc/sched_debug | tee -a $logfile
        fi

        if [ -f /proc/softirq ]; then
                echo softirq | tee -a $logfile
                cat /proc/softirq | tee -a $logfile
        fi

        if [ -f /proc/stat ]; then
                echo stat | tee -a $logfile
                cat /proc/stat | tee -a $logfile
        fi
        set +x
}

function setup_kernel_cmdline()
{
        local cmdline=$2
        local action=$1
        if [ "$action" = add  ]; then
                set -x
                grubby --args "$cmdline" --update-kernel $(grubby --default-kernel)
                set +x
        else
                grubby --remove-args "$cmdline" --update-kernel $(grubby --default-kernel)
        fi
}

#--------------------------------------------------
# for kernel sysctl operations, scheduler has many
# sysctls for tunning.
export SYSCTL_ORIGIN=/etc/sysctl.conf
function save_sysctl()
{
        # shellcheck disable=SC2048
        sysctl_or_debugfs_save $*
}

function restore_sysctl()
{
        # shellcheck disable=SC2048
        sysctl_or_debugfs_restore $*
}

# For rhel9, the sched.nr_migrate sysctl is provided as
# debug file, as /sys/kernel/debug/sched/nr_migrate,
# together with several other sched sysctls. So the setup,
# read, and verify must also pay attention to debugfs.
function sysctl_or_debugfs_get()
{
        local sysctl_dir=/proc/sys/
        local sched_dir=/sys/kernel/debug/sched

        local dir=$1
        local file=$2

        if test -f $sysctl_dir/$dir/$file; then
                echo "Using sysctl interface file: $sysctl_dir/$dir/$file" 1>&2
                cat $sysctl_dir/$dir/$file
                return 0
        elif test -f $sched_dir/${file#sched_}; then
                echo "Using debug fs interface file: $sched_dir/${file#sched_}" 1>&2
                cat $sched_dir/${file#sched_}
                return 0
        fi

        return 1
}

function sysctl_or_debugfs_save()
{
        local ret=0
        local key=$1
        local store_file=${2:-$key}
        local dir=$(echo $key | awk -F. '{print $1}')
        local file=$(echo $key | awk -F. '{print $2}')

        echo "saving $key to $store_file"
        sysctl_or_debugfs_get $dir $file | \
        awk '/\(.*\)/ {for (i=1;i<=NF;i++) if ($i ~ /\(.*\)/) {gsub("\\(|\\)","",$i); print $i; exit}} {print $0}' | \
        tee $store_file
        echo "saved $key result: $(cat $store_file)"
}

function sysctl_or_debugfs_restore()
{
        local ret=0
        local key=$1
        local store_file=${2:-$key}
        local dir=$(echo $key | awk -F. '{print $1}')
        local file=$(echo $key | awk -F. '{print $2}')

        echo "restoring $key from $store_file"
        sysctl_or_debugfs_set $dir $file "$(cat $store_file)"
        echo "restore $key result: $(sysctl_or_debugfs_get $dir $file)"
}

function sysctl_or_debugfs_set()
{
        local sysctl_dir=/proc/sys/
        local sched_dir=/sys/kernel/debug/sched

        local dir=$1
        local file=$2
        local setval=$3

        local ret=0

        if test -f $sysctl_dir/$dir/$file; then
                echo "Using sysctl interface file: $sysctl_dir/$dir/$file" 1>&2
                echo "echo \"$setval\" > $sysctl_dir/$dir/$file"
                echo "$setval" > $sysctl_dir/$dir/$file
                ret=$?
        elif test -f $sched_dir/${file#sched_}; then
                echo "Using debug fs interface file: $sched_dir/${file#sched_}" 1>&2
                echo "echo \"$setval\" > $sched_dir/${file#sched_}"
                echo "$setval" > $sched_dir/${file#sched_}
                ret=$?
        fi
        return $ret
}

function verify_sysctl_key()
{
        local key=$1
        local ret=0
        sysctl -N $1 &>/dev/null
        ret=$?
        if [ $ret -ne 0 ]; then
                local dir=$(echo $key | awk -F. '{print $1}')
                local file=$(echo $key | awk -F. '{print $2}')
                sysctl_or_debugfs_get $dir $file
                ret=$?
        fi
        return $ret
}

function setup_sys_ctl()
{
        local key=$1
        local value=$2
        local ret=0

        local dir=$(echo $key | awk -F. '{print $1}')
        local file=$(echo $key | awk -F. '{print $2}')
        sysctl_or_debugfs_set $dir $file $value
        ret=$?
        echo ${FUNCNAME[0]}: key=$key value=$value ret=$ret

        return $ret
}

function show_sysctl()
{
        local key=$1
        verify_sysctl_key $key
        return $?
}

function get_sysctl_key()
{
        local equation=$1
        echo $equation | awk -F '=' '{print $1}'
}

function get_sysctl_value()
{
        local equation=$1
        echo $equation | awk -F '=' '{print $2}'
}


#===================================
# Sched feature setup.
if test -f /sys/kernel/debug/sched/features; then
    SCHED_FEATURE_DEBUG_FILE="/sys/kernel/debug/sched/features"
elif test -f /sys/kernel/debug/sched_features; then
    SCHED_FEATURE_DEBUG_FILE="/sys/kernel/debug/sched_features"
fi

function debug_mount_init()
{
        mount /sys/kernel/debug &> /dev/null ||
        mount -t debugfs dbg /sys/kernel/debug &> /dev/null
}

function setup_sched_feature()
{
        local features=$*
        local ret=0
        local failures=""

        debug_mount_init

        for f in $features; do
                echo $f > $SCHED_FEATURE_DEBUG_FILE
                local tmp_ret=$?
                ret=$((ret | tmp_ret))
                [ $tmp_ret -ne 0 ] && failures="$failures $f"
        done
        [ -n "$failures" ] && echo FAIL: $failures
        return $ret
}

function show_sched_feature()
{
        local feature=$1
        debug_mount_init
        if [ -n "$feature" ]; then
                awk 'BEGIN{ RS=" "} /'$feature'/ {print $0}' $SCHED_FEATURE_DEBUG_FILE
                return
        fi
        cat $SCHED_FEATURE_DEBUG_FILE
}

function dump_cgroup_info()
{
        local pid=$1
        local cgroup=${2}
        echo ---------- cgroups of pid $pid --------------
        cat /proc/$pid/cgroup
        echo ---------------------------------------------

        check_cgroup_version

        if test -n "$cgroup"; then
                echo "[$cgroup_dir] Start $cgroup group info of $cgroup_dir:"
                local group_dir=$(grep $cgroup /proc/$pid/cgroup | cut -d: -f3)
                cgroup_get $group_dir $cgroup
                echo -e "[$cgroup_dir] End $cgroup cgroup info.\n"
                echo ---------------------------------------------
                echo
                return
        fi

        for cgroup in $(awk -F: '{print $2}' /proc/$pid/cgroup); do
                local group_dir=$(grep $cgroup /proc/$pid/cgroup | cut -d: -f3)
                echo "[$cgroup_dir] Start $cgroup group info of $cgroup_dir:"
                cgroup_get $group_dir $cgroup
                echo -e "[$group_dir] End $cgroup_dir:$cgroup cgroup info.\n"
                echo ---------------------------------------------
                echo
        done

        systemd-cgls | tee /dev/null
}

function install_libcgroup()
{
        local pkg=libcgroup.20210106.tgz
        [ -z "$LOOKASIDE" ] && LOOKASIDE=http://download.devel.redhat.com/qa/rhts/lookaside/
        rpm -q libcgroup-tools || yum -y install libcgroup-tools &>/dev/null
        rpm -q libcgroup-tools && return 0

        rpm -q cmake || yum -y install cmake &>/dev/null
        rpm -q pam-devel || yum -y install pam-devel bison flex
        curl -LkO  $LOOKASIDE/libcgroup.20210106.tgz || return 1
        tar -zxf $pkg
        pushd libcgroup
        sh bootstrap.sh
        make install -j $(nproc)
        popd
        which cgcreate &>/dev/null
}

function check_cgroup_version()
{
        [ -n "$CGROUP_VERSION" ] && return

        if mount | grep -qE "^cgroup2"; then
                CGROUP_ROOT=$(mount | awk '/cgroup2/ {print $3; exit}')
                cat $CGROUP_ROOT/cgroup.controllers
                nr_v2_controllers=$(awk '{print NF}' $CGROUP_ROOT/cgroup.controllers)
                if ((nr_v2_controllers > 0)); then
                        echo "Using cgroup V2" && CGROUP_VERSION=2
                        CGROUP_TASK_FILE=cgroup.procs
                        CGROUP_QUOTA_FILE=cpu.max
                        CGROUP_PERIOD_FILE=cpu.max
                else
                        echo "Using cgroup v1"
                        CGROUP_VERSION=1
                        CGROUP_ROOT=$(mount | grep cgroup | awk '/cgroup /{split($3, a, "cgroup"); print a[1]"cgroup"; exit}')
                        CGROUP_TASK_FILE=tasks
                        CGROUP_QUOTA_FILE=cpu.cfs_quota_us
                        CGROUP_PERIOD_FILE=cpu.cfs_period_us
                fi
        else
                echo "Using cgroup v1"
                CGROUP_VERSION=1
                CGROUP_ROOT=$(mount | grep cgroup | awk '/cgroup /{split($3, a, "cgroup"); print a[1]"cgroup"; exit}')
                CGROUP_TASK_FILE=tasks
                CGROUP_QUOTA_FILE=cpu.cfs_quota_us
                CGROUP_PERIOD_FILE=cpu.cfs_period_us
        fi

        gen_cgexec

        if cki_is_kernel_automotive; then
                CGROUP_EXEC=/tmp/cgexec.sh
        else
                CGROUP_EXEC=/usr/bin/cgexec.sh
        fi
        export CGROUP_VERSION
        export CGROUP_TASK_FILE
        export CGROUP_QUOTA_FILE
        export CGROUP_PERIOD_FILE
        export CGROUP_ROOT
        export CGROUP_EXEC
}

function cgroup_setup_memory()
{
        local cgroup_dir=$1
        local mem_size_max=$2 # can be format like 1g,2m,3t
        local mem_swap_max=$3 # can be format like 1g,2m,3t

        if [ "$CGROUP_VERSION" = 1 ]; then
                set -x
                cgroup=$CGROUP_ROOT/memory/$cgroup_dir
                mkdir -p $cgroup
                echo ${mem_size_max} > $cgroup/memory.limit_in_bytes
                echo ${mem_swap_max} > $cgroup/memory.memsw.limit_in_bytes
                set +x
        elif [ "$CGROUP_VERSION" = 2 ]; then
                local mem_oom_group=1
                cgroup=$CGROUP_ROOT/$cgroup_dir
                set -x
                mkdir -p $cgroup
                echo ${mem_size_max} > $cgroup/memory.max
                echo ${mem_swap_max} > $cgroup/memory.swap.max
                echo ${mem_oom_group} > $cgroup/memory.oom.group
                set +x
        fi
}

function cgroup_setup_cpu()
{
        local cgroup_dir=${1:-cpu,cpuacct}
        # For v2, it's empty string "", For v1, it's cpu.cfs_period_us.
        local period=$2
        local runtime=$3

        # kill rt user tasks if '+cpu' constroller can't be propagated to sub cgroup
        local force=${4:-1} #

        local cpu_mount
        local ret=0
        if [ "$CGROUP_VERSION" = 1 ]; then
                local controller=cpu
                cpu_mount=$(mount -t cgroup | awk '/'$controller',|'$controller' / {print $3}')
                local cgroup=$cpu_mount/$cgroup_dir
                mkdir -p $cgroup

                echo ${period} > $cgroup/cpu.cfs_period_us
                echo ${runtime} > $cgroup/cpu.cfs_quota_us

                [ $? -ne 0 ] && ((ret++))
        elif [ "$CGROUP_VERSION" = 2 ]; then
                controller=cpu
                echo "+$controller" >> $CGROUP_ROOT/cgroup.subtree_control
                cgroup=$CGROUP_ROOT/$cgroup_dir

                # if cgroup folder like: $CGROUP_ROOT/A/B/C
                local sub_path=$CGROUP_ROOT
                local sub_dir_name
                for sub_dir_name in ${cgroup_dir//\// }; do
                        [ "$sub_dir_name" = "${cgroup_dir//\/ }" ] && break
                        sub_path+="/$sub_dir_name"
                        mkdir $sub_path
                        echo "+$controller" >> $sub_path/cgroup.subtree_control || ((ret++))
                done

                mkdir -p $cgroup
                grep -qw $controller $cgroup/cgroup.controllers
                if [ $? -ne 0 ]; then
                        echo "$cgroup/cgroup.controllers: $controller is not enabled"
                        echo "rt tasks running:"
                        ps -AL -o pid,policy,args | grep -E "DL|FIFO|RR"
                        local rt_pids=$(ps -AL -o pid,policy,args | grep -E "RR|FF|DL" | grep -Ev "grep|\[" | awk '{print $1}')
                        [ "$force" = 1 ] && echo "Killing rt tasks" && kill $rt_pids
                        grep -qw $controller $cgroup/cgroup.controllers || { set +x; return 1; }
                fi
                echo "$runtime $period" > $cgroup/cpu.max
                [ $? -ne 0 ] && ((ret++))
        fi
        return $ret
}

declare -A CGROUP_RT_MAPS
function cgroup_reset_rt_runtime()
{
        local ret=0
        local grp

        if [ "$CGROUP_VERSION" = 2 ]; then
                echo "cgroup v2 is not supported for now, consider fix"
                return
        fi

        local cpu_cgroups=$(find /sys/fs/cgroup/cpu/*/ -maxdepth 1 -type f -name cpu.rt_runtime_us  -printf "%H%P\n")

        cgroup_root_rt_runtime_us=$(cat /sys/fs/cgroup/cpu/cpu.rt_runtime_us)
        cgroup_rt_period_us=$(cat /sys/fs/cgroup/cpu/cpu.rt_period_us)
        echo "old_cgroup_root_rt_runtime_us: $cgroup_root_rt_runtime_us"
        echo "old_cgroup_rt_period_us: $cgroup_rt_period_us"

        local new_runtime_us=950000
        echo "echo $new_runtime_us > /sys/fs/cgroup/cpu/cpu.rt_runtime_us"
        echo $new_runtime_us > /sys/fs/cgroup/cpu/cpu.rt_runtime_us

        for grp in $cpu_cgroups; do
                CGROUP_RT_MAPS["$grp"]=$(cat $grp)
                echo 0 > $grp || ret=1
                echo -n $grp: ${CGROUP_RT_MAPS["$grp"]}
                ((ret==0)) && echo " -----> 0" || echo
                ret=0
        done
}

function cgroup_restore_rt_runtime()
{
        local ret=0
        local grp

        if [ "$CGROUP_VERSION" = 2 ]; then
                echo "cgroup v2 is not supported for now, consider fix"
                return
        fi

        local cpu_cgroups=$(find /sys/fs/cgroup/cpu/*/ -maxdepth 1 -type f -name cpu.rt_runtime_us  -printf "%H%P\n")

        for grp in ${cpu_cgroups}; do
                echo ${CGROUP_RT_MAPS["$grp"]} > $grp || ret=1
                echo -n "$grp: 0 ----> "
                ((ret==0)) && echo ${CGROUP_RT_MAPS["$grp"]} || echo
                ret=0
        done

        echo "echo $cgroup_root_rt_runtime_us > /sys/fs/cgroup/cpu/cpu.rt_runtime_us"
        echo "echo $cgroup_rt_period_us > /sys/fs/cgroup/cpu/cpu.rt_period_us"
        echo $cgroup_root_rt_runtime_us > /sys/fs/cgroup/cpu/cpu.rt_runtime_us
        echo $cgroup_rt_period_us > /sys/fs/cgroup/cpu/cpu.rt_period_us
}

# For cgroup with hierachy /sys/fs/cgroup/cpu/a/b/c/d, need to recursively setup
# the cpu.rt_runtime_us from parent to child, and when clear them, need to go
# reverse path, that is from child to parent(d -> c > b > a)
# Reason why we need to setup it is otherwise, rt tasks can't be started if the
# current process is in a cpu cgroup where cpu.rt_runtime_us=0
cgroup_old_value_list=()
cgroup_sub_path_list=()

function cgroup_populate_rt_hierachy()
{
        [ -z "$CGROUP_VERSION" ] && check_cgroup_version
        if [ "$CGROUP_VERSION" = 2 ]; then
                echo "cgroup v2 is not supported for now, consider fix"
                return
        fi

        local new_runtime_us=950000
        cgroup_reset_rt_runtime

        local sub_path=""
        cpu_cgroup=$(grep -w cpu /proc/self/cgroup | awk -F: '{print $3}')
        echo -n "cpu cgroup: origin: $cpu_cgroup: rt_runtime_us:"
        cat /sys/fs/cgroup/cpu/$cpu_cgroup/cpu.rt_runtime_us

        for dir in ${cpu_cgroup////" "}; do
                sub_path+="/$dir"
                child_rt_runtime_us=$(cat /sys/fs/cgroup/cpu/$sub_path/cpu.rt_runtime_us)
                cgroup_old_value_list+=("$child_rt_runtime_us")
                cgroup_sub_path_list+=("$sub_path")
                echo "echo $new_runtime_us > /sys/fs/cgroup/cpu$sub_path/cpu.rt_runtime_us"
                echo $new_runtime_us > /sys/fs/cgroup/cpu$sub_path/cpu.rt_runtime_us
        done

        # If system slice was created for cpu cgroup, we run child cpu cgroup in that folder
        # as in a separated sibling cpu cgroup of system.slice, we can't get that much bandwidth
        # all used by system.slice-rt_runtime_us
        select_cgp="cpu:$cpu_cgroup/rtbw"
        cg_dir="$(echo $select_cgp | awk -F: '{print $2}')"
        cg_controller="$(echo $select_cgp | awk -F: '{print $1}')"
        echo "select_cgp=$select_cgp cg_dir=$cg_dir cg_controller=$cg_controller"
}

function cgroup_restore_rt_hierachy()
{
        [ -z "$CGROUP_VERSION" ] && check_cgroup_version
        if [ "$CGROUP_VERSION" = 2 ]; then
                echo "cgroup v2 is not supported for now, consider fix"
                return
        fi

        local sub_path
        local old_value
        local i=${#cgroup_sub_path_list[*]}
        ((--i))
        while ((i >= 0)); do
                sub_path=${cgroup_sub_path_list[$i]}
                old_value=${cgroup_old_value_list[$i]}
                [ -n "$old_value" ] && echo "echo $old_value > /sys/fs/cgroup/cpu$sub_path/cpu.rt_runtime_us"
                [ -n "$old_value" ] && echo $old_value > /sys/fs/cgroup/cpu$sub_path/cpu.rt_runtime_us
                ((--i))
        done
        cgroup_old_value_list=()
        cgroup_sub_path_list=()

        cgroup_restore_rt_runtime

        unset cgroup_old_value_list
        unset cgroup_sub_path_list
        unset CGROUP_RT_MAPS
}

function cgroup_create()
{
        local cgroup_dir=$1
        local controllers="${2//,/ }"

        local controller_mount
        local ret=0
        local controller
        local cgroup
        local force=0
        local level=0

        if [ "$CGROUP_VERSION" = 1 ]; then
                for controller in $controllers; do
                        controller_mount=$(cgroup_get_path / $controller)
                        cgroup=$controller_mount/$cgroup_dir
                        mkdir -p $cgroup
                        [ $? -ne 0 ] && ((ret++))
                done
        elif [ "$CGROUP_VERSION" = 2 ]; then
                # rt cpu group is not working in cgroup v2 in rhel9-Beta, and rt cpu group
                # would be disabled soon in rhel-9 Beta
                if [ "$force" = 1 ] && echo $controllers | grep -q cpu; then
                        echo "rt tasks running:"
                        ps -AL -o pid,policy,args | grep -E "DL|FIFO|RR"
                        local rt_pids=$(ps -AL -o pid,policy,args | grep -E "RR|FF|DL" | grep -Ev "grep|\[" | awk '{print $1}')
                        echo "Killing rt tasks" && kill $rt_pids
                fi

                for controller in $controllers; do
                        echo "+$controller" >> $CGROUP_ROOT/cgroup.subtree_control
                        [ $? -ne 0 ] && ((ret++))
                done
                cgroup=$CGROUP_ROOT/$cgroup_dir

                # if cgroup folder like: $CGROUP_ROOT/A/B/C
                # don't setup cgroup.sub_tree_control for the leaf cgroup(C), only leaf cgroup
                # can be used for running processes, while a leaf cgroup shouldn't provide
                # cgroup.subtree_control
                local sub_path=$CGROUP_ROOT
                local sub_dir_name
                local nr_sub_dirs=$(echo ${cgroup_dir//\// } | awk '{print NF}')
                for sub_dir_name in ${cgroup_dir//\// }; do
                        [ "$sub_dir_name" = "${cgroup_dir//\/ }" ] && break
                        sub_path+="/$sub_dir_name"
                        ((++level))
                        test -d $sub_path || mkdir $sub_path
                        ((level >= nr_sub_dirs)) && break
                        for controller in $controllers; do
                                echo "+$controller" >> $sub_path/cgroup.subtree_control || ((ret++))
                                [ $? -ne 0 ] && ((ret++))
                        done
                done

                mkdir -p $cgroup
                grep -qw $controller $cgroup/cgroup.controllers
                if [ $? -ne 0 ]; then
                        echo "$cgroup/cgroup.controllers: $controller is not enabled"
                        grep -qw $controller $cgroup/cgroup.controllers || { return 1; }
                fi
        fi

        echo ${FUNCNAME[0]}: succeed to create cgroup $cgroup

        return $ret
}

function __fix_cgroup_dir()
{
        local dir=$1
        local controller=$2

        if [ "$CGROUP_VERSION" = 1 ]; then
                local fixed_controller_dir=$(mount -t cgroup | awk '/'$controller',|'$controller' / {print $3}')
                local tgt_dir=$fixed_controller_dir/$dir/
        elif [ "$CGROUP_VERSION" = 2 ]; then
                local tgt_dir=$CGROUP_ROOT/$dir/
        fi

        echo $tgt_dir
}

function cgroup_get_path()
{
        local dir=$1
        local controller=$2
        __fix_cgroup_dir $dir "$controller"
}

function cgroup_destroy()
{
        local dir=$1
        local controllers="${2//,/ }"

        local path
        local tgt_dir
        local ret=0

        if [ "$CGROUP_VERSION" = 1 ]; then
                local fail_controllers=""
                local success_controllers=""
                for controller in $controllers; do
                        tgt_dir=$(__fix_cgroup_dir $dir "$controller")
                        test -d $tgt_dir || { echo "$tgt_dir doesn't exist!" && return; }
                        # kill the tasks in the cgroup
                        local nr_tasks=$(wc -l $tgt_dir/$CGROUP_TASK_FILE | awk '{print $1}')
                        ((nr_tasks > 0)) && kill $(cat $tgt_dir/$CGROUP_TASK_FILE)
                        rmdir $tgt_dir
                        if [ $? -ne 0 ]; then
                                echo "$controller:$tgt_dir failed to remove!"
                                fail_controllers+="$controller,"
                                ((ret++))
                        else
                                success_controllers+="$controller,"
                        fi
                done
                if ((ret==0)); then
                        echo "${FUNCNAME[0]}: $success_controllers:$tgt_dir succeed to be removed"
                else
                        echo "${FUNCNAME[0]}: $success_controllers:$tgt_dir fail to be removed"
                fi
        else
                # cgroup v2
                tgt_dir=$(__fix_cgroup_dir $dir "$controller")
                local nr_tasks=$(wc -l $tgt_dir/$CGROUP_TASK_FILE | awk '{print $1}')
                #((nr_tasks > 0)) && kill $(cat $tgt_dir/$CGROUP_TASK_FILE)
                ((nr_tasks > 0)) && echo 1 > $tgt_dir/cgroup.kill
                rmdir $tgt_dir || ((ret++))
                if ((ret==0)); then
                        echo "${FUNCNAME[0]}: $tgt_dir succeed to be removed"
                else
                        echo "${FUNCNAME[0]}: $tgt_dir fail to be removed"
                fi
        fi
}

declare -A CGROUP_FILE_MAP
CGROUP_FILE_MAP["memory.limit_in_bytes"]="memory.max"
CGROUP_FILE_MAP["memory.memsw.limit_in_bytes"]="memory.swap.max"
CGROUP_FILE_MAP["tasks"]="cgroup.procs"
CGROUP_FILE_MAP["cpu.shares"]="cpu.weight"
CGROUP_FILE_MAP["cpu.cfs_quota_us"]="cpu.max"

function v1_v2_file_map()
{
        local file_name=$1
        local file_dir=$2
        local k

        test -f $file_dir/$file_name && echo "$file_name" && return

        if echo "${CGROUP_FILE_MAP[*]}" | grep -qw "$file_name"; then
                for k in ${!CGROUP_FILE_MAP[*]}; do
                        if [ ${CGROUP_FILE_MAP[$k]} = "$file_name" ]; then
                                echo "${FUNCNAME[0]}: convert v2 file $file_name to v1 file $k" 1>&2
                                echo $k
                                return
                        fi
                done
        elif echo "${!CGROUP_FILE_MAP[*]}" | grep -qw "$file_name"; then
                echo "${FUNCNAME[0]}: convert v1 file $file_name to v2 file ${CGROUP_FILE_MAP["$file_name"]}" 1>&2
                echo "${CGROUP_FILE_MAP["$file_name"]}" && return
        fi

        echo $1
}

function cgroup_set()
{
        local dir=$1
        local controller=$2

        local ret=0
        local tgt_dir

        shift 2

        tgt_dir=$(__fix_cgroup_dir $dir $controller)
        test -d $tgt_dir

        [ $? -ne 0 ] && echo "No cgroup exist: $tgt_dir !" && return 1

        local file_name
        local file_path
        local file_value
        while [ $# -gt 0 ]; do
                file_name=$(echo $1 | awk -F= '{print $1}')
                file_path=$tgt_dir/$file_name
                file_value=$(echo $1 | awk -F= '{print $2}')
                if ! test -f $file_path; then
                        file_name=$(v1_v2_file_map $file_name $tgt_dir)
                        file_path=$tgt_dir/$file_name
                        test -f $file_path && ret=0 || echo "${FUNCNAME[0]}: No $file_name in $tgt_dir"
                fi
                echo $dir: file_name=$file_name, file_value=$file_value
                echo  "$file_value" > $file_path || ((ret++))
                shift 1
        done

        return $ret
}

function cgroup_get()
{
        local dir=$1
        local controllers="${2//,/ }"
        local other_files="${3//,/ }"
        local has_header=${4:-0}
        local extra
        local extra_0
        local cggf

        # if it's a cgroup print, show the headers
        [ $# -eq 2 ] && has_header=1

        extra_0=" -maxdepth 1"
        if [ "$other_files" != "" ]; then
                extra=" -name ${other_files// / -o -name }"
        fi
        if [ "$CGROUP_VERSION" = 1 ]; then
                for controller in $controllers; do
                        local tgt_dir=$(__fix_cgroup_dir $dir "$controllers")
                        # shellcheck disable=SC2044
                        for cggf in $(find $tgt_dir $extra_0 -type f $extra); do
                                nl=$(wc -l $cggf | awk '{print $1}')
                                if ((nl == 1)); then
                                        file_value=$(cat $cggf)
                                        if ((has_header)); then
                                                echo -n "$(basename $cggf)="
                                        fi
                                        echo "$file_value"
                                elif ((nl == 0)); then
                                        file_value=$(cat $cggf)
                                        if ((has_header)); then
                                                echo -n "$(basename $cggf)"
                                        fi
                                        echo "$file_value"
                                else
                                        echo "$(basename $cggf):"
                                        cat $cggf | awk '{printf("\t%s\n", $0)}'
                                fi
                        done
                done
        elif [ "$CGROUP_VERSION" = 2 ]; then
                local tgt_dir=$(__fix_cgroup_dir $dir "$controllers")
                # shellcheck disable=SC2044
                for cggf in $(find $tgt_dir $extra_0 -type f $extra); do
                        nl=$(wc -l $cggf | awk '{print $1}')
                        if ((nl == 1)); then
                                file_value=$(cat $cggf)
                                if ((has_header)); then
                                        echo -n "$(basename $cggf)="
                                fi
                                echo "$file_value"
                        elif ((nl == 0)); then
                                file_value=$(cat $cggf)
                                if ((has_header)); then
                                        echo -n "$(basename $cggf)="
                                fi
                                echo "$file_value"
                        else
                                echo "$(basename $cggf):"
                                cat $cggf | awk '{printf("\t%s\n", $0)}'
                        fi
                done
        fi

        return 0
}

# generate a cgexec.sh and locate it in /usr/bin
# Usage:
# cgexec.sh <dir_name> <controllers> <cmd>
function gen_cgexec()
{
        local file=cgexec.sh
        local path=$(pwd)
        local res
        local i

        for i in $(seq 1 10); do
                test -f $path/include/$file && res=$path/include/$file && break
                test -f $path/general/include/$file && res=$path/general/include/$file && break
                path=$path/..
        done

        echo "cgexec.sh in $res"

        if cki_is_kernel_automotive; then
                \cp $res /tmp -f
                test -f /tmp/cgexec.sh
        else
                \cp $res /usr/bin/ -f
                test -f /usr/bin/cgexec.sh
        fi
}

function cgroup_exec()
{
        local dir=$1
        local controllers="${2//,/ }"
        shift 2

        local tgt_file
        local controller
        local cgroup_exec_dirs
        local ret=1

        if [ "$CGROUP_VERSION" = 1 ]; then
                for controller in $controllers; do
                        local tgt_dir=$(__fix_cgroup_dir "$dir" "$controller")
                        local tgt_file=$tgt_dir/tasks
                        test -d $tgt_dir || { echo "${FUNCNAME[0]}: $tgt_dir doesnt exist" && continue; }
                        cgroup_exec_dirs+="$tgt_dir "
                done
                echo "${FUNCNAME[0]}: exec command in cgroups: $cgroup_exec_dirs"
        elif [ "$CGROUP_VERSION" = 2 ]; then
                local tgt_dir=$CGROUP_ROOT/$dir/
                tgt_file=$tgt_dir/cgroup.procs
                cgroup_exec_dirs="$tgt_dir"
        fi

        [ -z "$CGROUP_TASK_FILE" ] && check_cgroup_version

        cat > cgexec << EOF
cgroup_exec_dirs="$cgroup_exec_dirs"
cgroup_taskfile=$CGROUP_TASK_FILE
for cgdir in \$cgroup_exec_dirs; do
        echo \$\$ > \$cgdir/\$cgroup_taskfile
        [ \$? -ne 0 ] && echo "\$0: failed to migrate to cgroup" && exit 1
done
cat /proc/self/cgroup
exec bash -c "\$@"
EOF
        chmod +x cgexec

        ./cgexec "$@"
        ret=$?
        echo ${FUNCNAME[0]}: return=$?

        return $ret
}

function cgroup_classify()
{
        local dir=$1
        local controllers=${2//,/ }
        local pids=$3

        local tgt_dirs=""
        local tgt_file=""
        local ret=0

        if [ "$CGROUP_VERSION" = 1 ]; then
                for controller in $controllers; do
                        local tgt_dir=$(__fix_cgroup_dir "$dir" "$controller")
                        test -d $tgt_dir || { echo "${FUNCNAME[0]}: $tgt_dir doesnt exist" && continue; }
                        tgt_dirs+=" $tgt_dir"
                done
        elif [ "$CGROUP_VERSION" = 2 ]; then
                local tgt_dir=$(__fix_cgroup_dir "$dir" "$controllers")
                tgt_dirs+=" $tgt_dir"
        fi

        local move_pid
        for move_pid in $pids; do
                for tgt_dir in $tgt_dirs; do
                        tgt_file=$tgt_dir/$CGROUP_TASK_FILE
                        set -x
                        echo $move_pid >> $tgt_file
                        ret=$?
                        [ $ret -ne 0 ] && echo "failed to move $move_pid to $controller:$dir"
                        set +x
                done
        done

        return $ret
}

function cgroup_display()
{
        local dir=$1
        local controllers=${2//,/ }
        local controller

        [ -z "$controllers" ] && [ "$CGROUP_VERSION" = 1 ] && echo "controller is not provided" && return 1
        if [ "$CGROUP_VERSION" = 1 ]; then
                for controller in $controllers; do
                        local tgt_dir=$(__fix_cgroup_dir "$dir" "$controller")
                        test -d $tgt_dir || { echo "${FUNCNAME[0]}: $tgt_dir doesnt exist" && return 1; }
                        cgroup_get $dir $controller "$3"
                done
        else
                cgroup_get $dir "$controllers" "$3"
        fi
}

function cgroup_show_tasks()
{
        local dir=$1
        local controller=$2
        local ret=0


        if [ "$CGROUP_VERSION" = 1 ]; then
                set -x
                local fixed_controller_dir=$(mount -t cgroup | awk '/'$controller',|'$controller' / {print $3}')
                echo "cgroup tasks in: $fixed_controller_dir/$dir/tasks"
                cat $fixed_controller_dir/$dir/tasks
                ret=$?
                set +x
        else
                set -x
                echo "cgroup tasks in: $dir/cgroup.procs"
                cat $CGROUP_ROOT/$dir/cgroup.procs
                ret=$?
                set +x
        fi

        return $ret
}

function cgroup_count_tasks()
{
        local dir=$1
        local controller=$2
        local tgt_file

        if [ "$CGROUP_VERSION" = 1 ]; then
                local fixed_controller_dir=$(mount -t cgroup | awk '/'$controller',|'$controller' / {print $3}')
                echo "cgroup task count in: $fixed_controller_dir/$dir/tasks" 1>&2
                tgt_file=$fixed_controller_dir/$dir/tasks
        else
                echo "cgroup task count in: cgroup $dir/cgroup.procs" 1>&2
                tgt_file=$CGROUP_ROOT/$dir/cgroup.procs
        fi

        wc -l $tgt_file | awk '{print $1}'

        return $?
}

function cgroup_cpu_stat()
{
        local dir=$1
        local key=$2

        local throttled_time
        local nr_throttled
        local nr_periods
        local usage
        local usage_sys_ns
        local usage_user_ns
        local path=$(cgroup_get_path $dir cpu)

        if [ "$CGROUP_VERSION" = 1 ]; then
                cg_cpu_stat=cpu.stat
                cg_cpu_usage=cpuacct.usage
                usage=$(cat $path/$cg_cpu_usage)
                usage_user_ns=$(awk '/user_usec/ {print $2}' $path/cpuacct.stat)
                usage_sys_ns=$(awk '/system_usec/ {print $2}' $path/cpuacct.stat)
                nr_periods=$(awk '/nr_periods/ {print $2 }' $path/$cg_cpu_stat)
                throttled_time=$(awk '/throttled_time/ {print $2 }' $path/$cg_cpu_stat)
                nr_throttled=$(awk '/nr_throttled/ {print $2 }' $path/$cg_cpu_stat)
                cfs_period_us=$(cat $path/cpu.cfs_period_us)
                cfs_quota_us=$(cat $path/cpu.cfs_quota_us)
        else
                cg_cpu_stat=cpu.stat
                cg_cpu_usage=cpu.stat
                usage=$(awk '/usage_usec/ {print $2 * 1000}' $path/$cg_cpu_usage)
                usage_user_ns=$(awk '/user_usec/ {print $2 * 1000}' $path/$cg_cpu_usage)
                usage_sys_ns=$(awk '/system_usec/ {print $2 * 1000}' $path/$cg_cpu_usage)
                nr_periods=$(awk '/nr_periods/ {print $2}' $path/$cg_cpu_stat)
                throttled_time=$(awk '/throttled_time/ {print $2}' $path/$cg_cpu_stat)
                nr_throttled=$(awk '/nr_throttled/ {print $2}' $path/$cg_cpu_stat)
                cfs_period_us=$(cat $path/cpu.max | awk '{print $2}')
                cfs_quota_us=$(cat $path/cpu.max | awk '{print $1}')
        fi

        if ((0)); then
                echo usage=$usage usage_user_ns=$usage_user_ns usage_sys_ns=$usage_sys_ns
                echo nr_periods=$nr_periods throttled_time=$throttled_time nr_throttled=$nr_throttled
                echo cfs_period_us=$cfs_period_us cfs_quota_us=$cfs_quota_us
        fi

        case $key in
                throttled_time|nr_throttled|nr_periods|usage|usage_sys_ns|usage_user_ns)
                echo ${!key}
                ;;
                cfs_quota_us|cfs_period_us)
                echo ${!key}
                ;;
        esac
}

# Tell restraint dmesg checker to ignore such errors, so that we
# can get q clean/green job result view
function ignore_falsepositive_knownissues()
{
        local already_done="/mnt/scheduler_knownissues_done"
        test -f $already_done && return 0

        local filter_cfg="/usr/share/rhts/falsestrings"
        test -f $filter_cfg || touch $filter_cfg
        test -f $filter_cfg || { echo No $filter_cfg; return 0; }

        # shellcheck disable=SC2034
        local falsepositives_rhel8=(
                "EDAC DEBUG:"
                "ODEBUG: Out of memory"
        )
        # shellcheck disable=SC2034
        local falsepositives_rhel9=(
                "EDAC DEBUG:"
                "ODEBUG: Out of memory"
        )

        # shellcheck disable=SC2034
        local known_issues_rhel8=(
        )
        # shellcheck disable=SC2034
        local known_issues_rhel9=(
        )

        local list_name=""
        local list_names=""

        local os=$(awk -F= '/^ID=/ {gsub("\"","",$2);print $2}' /etc/os-release)
        local major=$(awk -F= '/^VERSION_ID=/ {gsub("\"","",$2);split($2,a,".");print a[1]}' /etc/os-release)

        if [ "$os$major" = "rhel9" ] || [ "$os$major" = "ceontos9" ]; then
                list_names="falsepositives_rhel9 known_issues_rhel9"
        elif [ "$os$major" = "rhel8" ] || [ "$os$major" = "ceontos8" ]; then
                list_names="falsepositives_rhel8 known_issues_rhel8"
        fi

        if [ -z "$list_names" ]; then
                echo "No known falsepositives or knownissues to filter out.."
                return
        fi

        for list_name in $list_names; do
                local i
                # shellcheck disable=SC1087,SC1083
                local nr_items="$(eval echo \${#$list_name[*]})"
                local line=""
                echo $list_name: $nr_items items
                for ((i=0; i<nr_items; i++)); do
                        # shellcheck disable=SC1087,SC1083
                        line="$(eval echo \${$list_name[$i]})"
                        grep -Eq "^$line" $filter_cfg && echo "\"$line\" already in $filter_cfg" && continue
                        echo "$line" >> $filter_cfg
                        echo "\"$line\" newly added to $filter_cfg"
                done
        done
        touch $already_done

        return 0
}

# Test case for the cgroup helper functions
if ((0)); then
        check_cgroup_version
        cgroup_get_path / cpu
        #cgroup_setup_cpu A/B/C "" max
        cgroup_create A/B/C cpu,memory,pids
        cgexec.sh A/B/C cpu stress-ng --cpu 1 -t 10
        cgroup_cpu_stat A/B/C usage
        cgroup_get A cpu cpu.weight
        cgroup_get A cpu cpu.max,cpu.weight 1
        # contains the file name in result like A=xxxx
        cgroup_get A cpu cpu.weight 1
        cgroup_get A/B/C cpu
        cgroup_display A/B/C "cpu" "cpu.weight cpu.cfs_period_us cpu.cfs_quota_us"
        cgroup_set A cpu cpu.shares="1000"
        cgroup_set A/B cpu cpu.shares="2000"
        cgroup_set A/B/C cpu cpu.shares="3000"
        cgroup_get A/B/C cpu cgroup.procs
        cgroup_exec A/B/C cpu timeout 20 "openssl speed -multi $(nproc --all) >/dev/null 2>&1 &>/dev/null &"
        cgroup_exec "world" "cpu,memory" "stress-ng --cpu 1 -t 10 &"
        cgroup_exec "world" "cpu,memory" "sleep 10"
        echo ret=$?
        sleep 2
        cgroup_display A/B/C "cpu" "cpuacct.stat cpu.stat cgroup.procs"
        cgroup_destroy A/B/C cpu,memory,pids
        cgroup_destroy A/B cpu,memory,pids
        cgroup_destroy A cpu,memory,pids
fi

ignore_falsepositive_knownissues
