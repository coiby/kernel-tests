#! /bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/1452675
#   Description: unbound kworkers being activated on masked CPUs
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

# Include rhts environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh ||  exit 1

trap 'Cleanup' SIGHUP SIGINT SIGQUIT SIGTERM SIGUSR1

tracing_dir=/sys/kernel/debug/tracing
nr_cpu=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)
max=$((nr_cpu - 1))

Cleanup() {
	true
}

# Convert cpu number list to bitmask, such as
# input:  list="12 13 14 15 16 17 18 19 20 21 22 23 32"
# result: 1,00fff000
# then echo 1,00fff000 > /sys/kernel/debug/tracing/tracing_cpumask
function get_cpumask() {
	local tmp=""
	local index=0
	local mask=""
	local c
	declare -a package_cpus_mask
	local cpu_list=$*
	for index in $(seq 0 $((1024 / 32))); do
		package_cpus_mask[$index]=0
	done

	for c in $cpu_list; do
		index=$((c / 32))
		package_cpus_mask[$index]=$((package_cpus_mask[$index] | ((1 << (( c - ((32*index)) )) ))))
	done
	for index in ${!package_cpus_mask[*]}; do
		package_cpus_mask[$index]=$(printf "%08x" ${package_cpus_mask[$index]})
		mask=${package_cpus_mask[$index]},$mask
	done
	echo $mask | awk -F, 'BEGIN{i=1;out=""}{while($i == "00000000" && i<NF) i++}END{for (;i<=NF;i++) out=out","$i; gsub("^,|,$","",out);printf("%s\n", out);}'
}

rlJournalStart
	rlPhaseStartSetup
		reason=""
		rlRun "yum -y install tuna" || reason="(tuna)"
		# Only x86_64 have this
		rlRun "yum -y install rt-tests" 0-255 || reason+="(rt-tests)"
		mount | grep debug || mount -t debugfs dd /sys/kernel/debug
		rlRun "nr_sockets=$(lscpu |  awk '/Socket/ {print $2}')"  0-255
		# shellcheck disable=SC2154
		if ((nr_sockets < 2)); then
			reason+="(SocketNumber)"
		fi
		if [ -n "$reason" ]; then
			report_result "Skipped$reason" PASS
			rlPhaseEnd
			rlJournalPrintText
			exit 0
		fi
	rlPhaseEnd

	rlPhaseStartTest
		old_cpumask=$(cat /sys/devices/virtual/workqueue/cpumask)
		old_numa=$(cat /sys/bus/workqueue/devices/writeback/numa)
		rlRun "tuna -S1 -i"
		package_cpus="$(sh package.sh 1)"
		rlLogInfo "$package_cpus"
		rlRun "package_nr_cpus="$(echo $package_cpus | awk '{print NF}')"" 0-255
		package_cpus_mask=0
		# For 1ffffffff such kind, covert to 1,ffffffff with ',' as seperator
		package_cpus_mask=$(get_cpumask "$package_cpus")
		rlLogInfo "package_cpus_mask=$package_cpus_mask"
		rlLogInfo "grouped package_cpus_mask=$package_cpus_mask"
		package_cpus_mask_hex=$(echo | awk -v e=$package_cpus_mask '{printf "%x\n", e}')
		rlLogInfo "cpumask hex: $package_cpus_mask_hex"
		rlRun "echo 1 >  /sys/devices/virtual/workqueue/cpumask"
		rlRun "echo 0 >   /sys/bus/workqueue/devices/writeback/numa"
		# clean the buffer
		rlRun "> /sys/kernel/debug/tracing/trace"
		rlRun "echo 'cpu != 0 && req_cpu == 5120'  > /sys/kernel/debug/tracing/events/workqueue/workqueue_queue_work/filter"
		rlRun "echo 1 > /sys/kernel/debug/tracing/events/workqueue/workqueue_queue_work/enable"
		rlRun "echo $package_cpus_mask_hex > /sys/kernel/debug/tracing/tracing_cpumask"
		# it's defined with rlRun parameter.
		# shellcheck disable=SC2154
		rlLogInfo "taskset -c ${package_cpus// /,} cyclictest -- -a ${package_cpus// /,} -t $package_nr_cpus -m -d 30 -D 350 --quiet &"
		taskset -c ${package_cpus// /,} cyclictest -- -a ${package_cpus// /,} -t $package_nr_cpus -m -d 30 -D 350 --quiet > /dev/null &
		pid=$!
		rlLogInfo "Sleeping 180s"
		sleep 180
		rlRun "grep -v vmstat $tracing_dir/trace | grep -v queue_work"
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "echo 0 > $tracing_dir/events/enable"
		rlRun "echo nop > $tracing_dir/current_tracer"
		rlRun "echo '!cpu != 0 && req_cpu == 5120'  > /sys/kernel/debug/tracing/events/workqueue/workqueue_queue_work/filter" 0-255
		rlRun "tuna -S1 -I" 0-255 "include the isolated socket"
		rlRun "ps -p $pid -o args | grep cyclictest && kill $pid" 0-255
		rlRun "echo $old_cpumask > /sys/devices/virtual/workqueue/cpumask" 0-255
		rlRun "echo $old_numa > /sys/bus/workqueue/devices/writeback/numa" 0-255
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

