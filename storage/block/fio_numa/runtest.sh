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
		rlRun "taskset -c $cpu fio --output=/root/fio_perf_randwrite_$node --output-format=terse --terse-version=4 \
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
	TEST_DEV=$(lsblk | grep -oE "sda|vda|nvme0n1" | head -1)
	FIO_PERF_FIELDS=("read iops")
	field="${FIO_TERSE_FIELDS["$FIO_PERF_FIELDS"]}"
	while [ $node -lt $nodes_num ]; do
		cpu=$(eval echo '$'NODE_${node}_CPU)
		rlRun "taskset -c $cpu fio --output=/root/fio_perf_randread_$node --output-format=terse --terse-version=4 \
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
	rlLog "min: $min, max:$max"

	if [ `echo "$min*1.1 > $max" |bc` -eq 1 ] ; then
		pass_msg="Performance comparison: min:$min * 1.1 > max:$max"
		rlPass "${pass_msg}"
		rstrnt-report-result ${pass_msg} PASS 0
	else
		fail_msg="Performance comparison: min:$min * 1.1 < max:$max"
		rlFail "${fail_msg}"
		rstrnt-report-result "${fail_msg}" FAIL 0
	fi
}

function runtest
{
	local node=0
	local nodel=1
	nodes_num=$(numactl -H | grep available | awk '{print $2}')
	if [ $nodes_num -eq 1 ]; then
		rstrnt-report-result "There is only one node on this server" SKIP 0
		exit
	fi
	rlLog "There are $nodes_num nodes on this server:"
	rlRun "numactl -H"
	while [ $node -lt $nodes_num ]; do
		eval "NODE_${node}_CPU=$(numactl -H | grep "node.*cpus" | head -$nodel | tail -1 | awk '{print $4}')"
		((node++))
		((nodel++))
	done
	rlLog "Start  randwrite_fio tests"
	randwrite_fio
	rlLog "compare_min_max $NODES_RW"
	compare_min_max $NODES_RW

	rlLog "Start randread_fio tests"
	randread_fio
	rlLog "compare_min_max $NODES_RR"
	compare_min_max $NODES_RR
}

cki_main
