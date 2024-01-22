#!/bin/bash
# shellcheck disable=SC2128
#   vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1197899
#   Description: Bug 1157802 - vmstat: on-demand vmstat workers
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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


# first nohz_full cpu, for ppc64le from 8.1, this can be 0. But we must leave more house
# keeping cpu to make cpu0 can be nohz_full.
first_cpu=2
last_cpu=

# Check the benchmark value for the current scheduler.After the new design of
# vmstat worker. less overall should be observed.This result needs to be compareed
# with the old version kernel without this fix.
# Use the hackbench written by Ingo Mona, the tool has been integrated in perf tools.
function test_sched_hackbench(){
	local loops=8000
	rlLogInfo "Get the hachbench result of the scheduler."
	# this is defined in 'rlRun' parameter below Line 193.
	# shellcheck disable=SC2154
	rlLogInfo "1. use pipe, $CpuCount groups, loop $loops times."
	# use pipe
	for i in $(seq 3);do
		rlRun "perf bench sched messaging -g ${CpuCount} -l $loops -p|tee -a benchmark-pipe"
		sleep 1;
	done
	local Average=$(awk '{sum+=$1}END{print sum/NR}' benchmark-pipe)
	rlLogInfo "Averagetime=$Average"
	return $?
}

# 1628402
function check_smt_clock_source()
{
	! test -f /sys/devices/system/cpu/smt/control && return
	! grep tsc /sys/devices/system/clocksource/clocksource0/available_clocksource && return
	# If cpu i not smt supported. Skip.
	grep 1 /sys/devices/system/cpu/smt/active  || return

	rlPhaseStartTest  "clock source check 1628402"
	rlRun -l "cat /sys/devices/system/clocksource/clocksource0/available_clocksource"
	rlRun -l "cat /sys/devices/system/clocksource/clocksource0/current_clocksource"
	rlLogInfo "disabling smt ..."
	local old=$(cat /sys/devices/system/cpu/smt/control)
	local old_clk=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)
	rlRun "echo tsc > /sys/devices/system/clocksource/clocksource0/current_clocksource"
	local i
	for i in $(seq 1 10); do
		rlRun "echo off > /sys/devices/system/cpu/smt/control"
		sleep 1
		rlAssertGrep tsc /sys/devices/system/clocksource/clocksource0/current_clocksource
		cat sys/devices/system/clocksource/clocksource0/current_clocksource
		rlRun "echo on > /sys/devices/system/cpu/smt/control"
		sleep 1
	done

	rlRun "echo $old > /sys/devices/system/cpu/smt/control"
	rlRun "echo $old_clk > /sys/devices/system/clocksource/clocksource0/current_clocksource" 0-255
	rlPhaseEnd
}

# bz1694877
function check_nohz_loadavg()
{
	local i
	local j

	rlPhaseStartTest bz1694877

	rlRun "gcc $DIR_SOURCE/bz1694877.c -o bz1694877_load"
	for ((i=0; i<6; i++)); do
		local old_load_1=$(awk '{print $1}' /proc/loadavg)
		for ((j=0; j<$(nproc --all); j++)); do
			chrt -f 3 taskset -c $j timeout 10 ./bz1694877_load &
		done
		sleep 10
		local new_load_1=$(awk '{print $1}' /proc/loadavg)
		rlLogInfo "old_load=$old_load_1 new_load=$new_load_1"
		pkill -9 -f bz1694877_load
		if test $(echo $new_load_1 \> $(nproc --all) \* 0.5 | bc) -eq 1; then
			rlReport bz1694877 FAIL
			return
		else
			rlReport bz1694877 PASS
			return
		fi
	done

	rlPhaseEnd
}

# Check how long is the local timer interval for an isolated cpu.
# Before this test, kernel commandline needs to be set to disable nmi_watchdog
# and  isolate the (nCpu -2) cpus;
function test_timer_interval(){
	rlLogInfo "Move the RCU procs onto core 0"
	rlRun "for i in `pgrep rcu|awk 'ORS=\" \" {print}'`;do taskset -pc 0 \$i ; done" 0-254

	rlLogInfo "Prevent any write back from occuring on trading cores"
	rlRun -l "echo 1 > /sys/bus/workqueue/devices/writeback/cpumask" 0-254

	rlLogInfo "bdi-flush threads are NUMA-affined to be PCI-local to the storage adapter,prevent it"
	rlRun "echo 0 > /sys/bus/workqueue/devices/writeback/numa"
	local interval=120
	rlLogInfo "Prevent this running every 2 seconds and interupting us. The vmstat worker.Timer interrupt."
	rlRun "sysctl vm.stat_interval=$interval"
	# Now run the tests.Let the process run on the last isolated cpu.
	rlRun -l "taskset -c $last_cpu bash -c \"while true; do :; done;\" &"
	set -x
	pid=$!
	set +x

	rlLogInfo "Monitor nonvoluntary_ctxt_switches and timer interupts:"
	# shellcheck disable=SC2034
	local loop=6
	rlRun -l "while ((--loop>0)); do cat /proc/$(pgrep -f 'while true')/status| grep non;\
		cat /proc/interrupts| grep \"Local timer\" |\
		awk '{print \"local timer interrupts:         \" $'$((CpuCount+1))'}';\
		echo \"------\" ;sleep 10; done;"

	timerVal0="$(cat /proc/interrupts| grep "Local timer" |awk '{print $'$((CpuCount+1))'}')"
	rlLogInfo "timer=$timerVal0"
	# shellcheck disable=SC2034
	nv_sched0=\"$(cat /proc/$(pgrep -f 'while true')/status| grep non)\"
	#the non vulentory scheule times should be not changed.
	rlRun "sleep $interval" 0-254
	timerVal1="$(cat /proc/interrupts| grep "Local timer" |awk '{print $'$((CpuCount+1))'}')"
	rlLogInfo "timer=$timerVal1"
	# shellcheck disable=SC2034
	nv_sched1=\"$(cat /proc/$(pgrep -f 'while true')/status| grep non)\"
	#rlAssertEquals "nv_shecd0 should equal to nv_sched1" "$nv_sched0" "$nv_sched1"
	rlLogWarning "Local timer part is not fixed."
	if ((first_cpu == 0)); then
		if [ "$timerVal0" != "$timerVal1" ]; then
			rlLogWarning "$timerVal0 : $timerVal1"
			rlReport "bz1666614" WARN
		else
			rlReport "bz1666614" PASS
		fi
	fi
	rlRun "kill -9 $pid" 0-254
	return $?
}

function bz1837380_tick_broadcast_offline()
{
	uname -r | grep rt && rlIsRHEL "<=8.5" && { report_result rt_cpu_offline_nohz SKIP; return; }
	rlPhaseStartTest bz1837380
	which stress-ng &>/dev/null || { pushd ../../../include/scripts/; sh stress.sh; popd; }
	which stress-ng &>/dev/null || { rlReport "bz1837380_cpu_offline" WARN; return; }
	rlLog "offline nohzfull cpu for checking tick warnings"
	rlRun "stress-ng --cpu-online $last_cpu --pathological -t 60"
	rlReport bz1837380 PASS
	rlPhaseEnd
}

function bz1157802()
{
	if ! rlIsRHEL ">=7.2";then
		rlLogWarning "The on demand vmstat worker is added in RHEL-7.2"
		return 0;
	fi
	# first reboot and second reboot.
	local rebootflag_f=${DIR_DEBUG}/REBOOT_${FUNCNAME}_F
	local rebootflag_s=${DIR_DEBUG}/REBOOT_${FUNCNAME}_S

	rlLogInfo "Bug 1157802 - vmstat: on-demand vmstat workers"

	case $(rlGetPrimaryArch) in
		x86_64|ppc64|ppc|ppc64le|aarch64|i386|i686|s390x)
			rlRun "CpuVendor=$(lscpu |grep -m 1 "Vendor ID" |awk -F ':'  '{print $2}'|sed 's/ //g')"
			rlRun "CpuFamily=$(lscpu |grep -m 1 "CPU family" |awk -F ':' '{print $2}'|sed 's/ //g')"
			rlRun "Model=\"$(lscpu |grep -m 1 "Model" |awk -F ':' '{print $2}'|sed 's/ //g')\""
			rlRun "NumaNode=$(lscpu |grep -m 1 "NUMA node" |awk -F ':' '{print $2}'|sed 's/ //g')"
			rlRun "CpuCount=$(grep -wc processor /proc/cpuinfo)"
			last_cpu=$((CpuCount-1))

			# For ppc64le since 8.1. Bug 1666614 - [IBM 8.1 FEAT] Full tickless kernel (including cpu0) (CORAL)
			if rlIsRHEL ">=8.1" && uname -m | grep ppc64le; then
				((CpuCount < 1)) && rlLogWarning "Test needs number of cpu >= 4." && rlDie "there is no any cpu!"
				rlLog "Try to set nohz_full starts from CPU 0 in ppc64le ... (Bug 1666614)"
				first_cpu=0
				# Leave one housekeeping cpu.
				last_cpu=$((CpuCount-2))
			fi

			if [ -f "$rebootflag_s" ];then
				rlAssertNotGrep ".*isolcpus.*nohz_full=.* nmi_watchdog=.* nohz=.*" /proc/cmdline "-E"
				[ $? -ne 0 ] && rlLogInfo "Commandline has been reset to normal $(cat /proc/cmdline)"
				return 0;
			fi
			if [ ! -f "$rebootflag_f" ];then
				test_sched_hackbench
				check_smt_clock_source
				((CpuCount < 4)) && rlLogWarning "Test needs number of cpu >= 4." && return 1;
				rlLogInfo "Set kernel cmdline to isolabe some cpus and enable adjustive ticks."
				rlRun "grubby --args=\"nohz_full=$first_cpu-$last_cpu rcu_nocbs=$first_cpu-$last_cpu nmi_watchdog=0 nohz=on nowatchdog nosoftlockup\"\
					--update-kernel=$(grubby --default-kernel)"
				touch $rebootflag_f
				rhts-reboot
			else
				# test how long a task on an isolated cpu can work continuously without being intterupted.
				test_timer_interval
				check_smt_clock_source
				check_nohz_loadavg
				bz1837380_tick_broadcast_offline
				# set the kernel cmdline to the default.
				rlRun -l "grubby --remove-args=\"rcu_nocbs=$first_cpu-$last_cpu nohz_full=$first_cpu-$last_cpu nmi_watchdog=0 nohz=on nowatchdog nosoftlockup\"\
					--update-kernel=$(grubby --default-kernel)"
				rlLogInfo "$FUNCNAME: reboot the machine"
				rlRun "touch $rebootflag_s"
				rhts-reboot
			fi
			rlRun "pidstat > pidstat.log"
			rlFileSubmit pidstat.log
			;;
		*)
			rlLogInfo "$(uname -m) is not intended to be tested."
			;;
	esac
}
