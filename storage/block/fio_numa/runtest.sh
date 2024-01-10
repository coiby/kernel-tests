#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#
FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)
NODES_RW=""
NODES_RR=""

declare -A FIO_TERSE_FIELDS
FIO_TERSE_FIELDS=(
        # Read status
        ["read io"]=6
        ["read bandwidth"]=7
        ["read iops"]=8
        # Write status
        ["write io"]=47
        ["write bandwidth"]=48
        ["write iops"]=49
)
# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh || exit 1

function randwrite_fio()
{
    local node=0 filed value
    FIO_PERF_FIELDS=("write iops")
    field="${FIO_TERSE_FIELDS["$FIO_PERF_FIELDS"]}"
    while [ $node -lt $nodes_num ]; do
        cpu=$(eval echo '$'NODE_${node}_CPU)
        cki_run "taskset -c $cpu fio --output=/root/fio_perf_randwrite_$node --output-format=terse --terse-version=4 \
        --bs=4K --size=1g --ioengine=libaio --iodepth=64 --iodepth_batch_submit=16 \
        --iodepth_batch_complete_min=16 --filename=/root/fio.tmp \
        --direct=1 --runtime=20 --numjobs=1 --size=1g --rw=randwrite --name=randwrite-test -group_reporting"
        value="$(cut -d ';' -f "$field" "/root/fio_perf_randwrite_$node")"
        rstrnt-report-log -l /root/fio_perf_randwrite_$node
        NODES_RW+=" $value"
        ((node++))
    done
}

function randread_fio()
{
    local node=0 filed value
    TEST_DEV=$(lsblk | grep "/boot$" | grep -oE "sd[a-f]|vda|nvme0n1" | head -1)
    if [ -z $TEST_DEV ]; then
        cki_run "lsblk"
        cki_abort_task "Didn't get the boot disk"
    fi
    FIO_PERF_FIELDS=("read iops")
    field="${FIO_TERSE_FIELDS["$FIO_PERF_FIELDS"]}"
    while [ $node -lt $nodes_num ]; do
        cpu=$(eval echo '$'NODE_${node}_CPU)
        cki_run "taskset -c $cpu fio --output=/root/fio_perf_randread_$node --output-format=terse --terse-version=4 \
        --bs=4K --size=1g --ioengine=libaio --iodepth=64 --iodepth_batch_submit=16 \
        --iodepth_batch_complete_min=16 --filename=/dev/${TEST_DEV} \
        --direct=1 --runtime=20 --numjobs=1 --rw=randread --name=randread-test -group_reporting"
        value="$(cut -d ';' -f "$field" "/root/fio_perf_randread_$node")"
        rstrnt-report-log -l /root/fio_perf_randread_$node
        NODES_RR+=" $value"
        ((node++))
    done
}

function compare_min_max()
{
    local min=$1
    local max=$1

    for i in "$@"; do
        ((i > max)) && max=$i
        ((i < min)) && min=$i
    done
    echo "min: $min, max:$max"

    if [ `echo "$min*1.15 > $max" |bc` -eq 1 ] ; then
        echo "Pass: Performance comparison: min:$min * 1.15 > max:$max"
        return 0
    else
        echo "Fail: Performance comparison: min:$min * 1.15 < max:$max"
        return 1
    fi
}

function runtest
{
    local node=0
    local nodel=1
    local failure=0
    avail_num=$(numactl -H | grep available | awk '{print $2}')
    nodes_num=$(numactl -H | grep -E "node\ [0-9]\ cpus:\ [0-9]" | wc -l)
    cki_run "numactl -H"
    if ((nodes_num == 1 || avail_num == 1)); then
        echo "Skip: There is only one node on this server"
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result "${RSTRNT_TASKNAME}" SKIP 0
        exit
    fi
    echo "There are $nodes_num nodes on this server:"
    while [ $node -lt $nodes_num ]; do
        eval "NODE_${node}_CPU=$(numactl -H | grep -E "node\ [0-9]\ cpus:\ [0-9]" | head -$nodel | tail -1 | awk '{print $4}')"
        ((node++))
        ((nodel++))
    done
    echo "Start  randwrite_fio tests"
    randwrite_fio
    echo "compare_min_max $NODES_RW"
    if compare_min_max $NODES_RW; then
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result "compare_min_max NODES_RW" PASS 0
    else
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result "compare_min_max NODES_RW" FAIL 0
        failure=1
    fi

    echo "Start randread_fio tests"
    randread_fio
    echo "compare_min_max $NODES_RR"
    if compare_min_max $NODES_RR; then
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result "compare_min_max NODES_RR" PASS 0
    else
        [[ -n $RSTRNT_TASKID ]] && rstrnt-report-result "compare_min_max NODES_RR" FAIL 0
        failure=1
    fi
    return $failure
}

if ! runtest; then
    # if running as restraint job, the test result is already reported as subtests
    # don't exit with values different of 0. Otherwise, restraint reports it as a separate subtest
    if [[ -z $RSTRNT_TASKID ]]; then
        exit 1
    fi
fi
