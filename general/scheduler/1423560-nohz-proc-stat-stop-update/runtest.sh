#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/1423560
#   Description: /proc/stat stop updates on nohz cpu.
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
. ../include/runtest.sh

tracing_dir=/sys/kernel/debug/tracing
nr_cpu=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)
max=$((nr_cpu - 1))
((max >= 3)) && max=3
isolated_cpus="1-$max"

# default 20m
export RUN_TIME=${RUN_TIME:-1200}
trace=0

function cleanup()
{
	rlRun "sed -i '/^isolated_cores=/d' $cfg_file" 0-255
	rlRun "sed -i 's/^isolate_managed_irq=.*$/# &/' $cfg_file"

	test -f $save_cfg_file && ln=$(cat $save_cfg_file)
	echo "restoring default isolated_cores parameters"
	[ -n "$ln" ] && sed -i ''$ln's/^#//' $cfg_file

	active=$(cat reboot_1423560)
	if [ "$active" = "" ]; then
		rlRun "tuned-adm off"
	else
		rlRun "tuned-adm profile $active" 0
	fi

	nohz_cleanup_commandline
	nohz_check_commandline
	test -f $save_cfg_file && rm -f $save_cfg_file
}

#cfg_file=/etc/tuned/realtime-variables.conf
cfg_file=/etc/tuned/realtime-virtual-host-variables.conf
save_cfg_file=/mnt/1423560_ln

nohz_params=" skew_tick isolcpus intel_pstate nosoftlockup tsc nohz nohz_full rcu_nocbs irqaffinity"

function nohz_cleanup_commandline()
{
	for k in $nohz_params; do
		set -x
		grubby --remove-args $k --update-kernel DEFAULT
		set +x
	done
}

function nohz_check_commandline()
{
	local grep_param=${nohz_params// / -e }
	set -x
	grubby --info DEFAULT
	grubby --info DEFAULT | grep $grep_param && report_result nohz_cleanp FAIL
	set +x
}

rlJournalStart
	if test -f reboot_1423560_2;  then
		rlPhaseStartTest
			rlRun "grep nohz_full /proc/cmdline" 1-255
			rlLog "Test finished, removed nohz kernel parameters."
		rlPhaseEnd
		rlPhaseStartCleanup
			rlRun "killall stress" 0-255
		rlPhaseEnd
	elif ! test -f reboot_1423560; then
		rlPhaseStartSetup
			if ((nr_cpu < 2)) || ! uname -r | grep -Eq "x86_64|aarch64"; then
				report_result "skip_cpu_${nr_cpu}" SKIP
				rlPhaseEnd
				rlJournalEnd
				exit 0
			fi
			rlLogInfo "Compile stress ..."
			_wget_compile_stress
			which stress || cp $SCHED_STRESS_PATH/stress /usr/bin/
			which stress || rlDie "No stress binary can be used."
			# aarch64 don't have the tuned-nfv-host-profile
			if ! uname -r | grep x86_64; then
				rlRun "grubby --args \"nohz=on isolcpus=$isolated_cpus nohz_full=$isolated_cpus rcu_nocbs=$isolated_cpus mce=ignore_ce nosoftlockup intel_idle.max_cstate=1 intel_pstate=disable\" --update-kernel DEFAULT"
				rlRun "touch reboot_1423560"
				grubby --info DEFAULT
				rhts-reboot
			fi

			# this file won't exist when tuned is not installed, the
			# reboot file will be empty; when tuned has already been
			# started, throughput-performance will be the default
			# profile, and be present in active_profile; otherwise
			# the reboot file will contain whatever profile the user
			# has set.
			cat /etc/tuned/active_profile > reboot_1423560
			rlLog "original active tuned provile: $(cat reboot_1423560)"

			rlRun "yum install -y tuned"
			rlRun "systemctl start tuned"

			rlLog "enable tuned service"
			rlRun "systemctl enable tuned"

			rlLog "start tuned service"
			rlRun "systemctl start tuned"

			rlRun "systemctl status tuned" -l 0-255

			#rlRun "yum -y install tuned-profiles-realtime" 0-255
			rlRun "yum -y install tuned-profiles-nfv-host.noarch" 0-255

			grep "^isolate_managed_irq=Y" $cfg_file || rlRun "echo \"isolate_managed_irq=Y\" >> $cfg_file"

			# Save the old  config
			grep "^isolated_cores=" $cfg_file
			ln=$(grep -n ^isolated_cores $cfg_file | awk -F: '{print $1; exit}')
			touch $save_cfg_file && echo $ln > $save_cfg_file

			# comment out the below line
			# isolated_cores=${f:calc_isolated_cores:1}
			sed -i 's/^isolated_cores=/#&/' $cfg_file

			rlRun "echo \"isolated_cores=$isolated_cpus\" >> $cfg_file"

			rlRun "tuned-adm profile realtime-virtual-host" 0-255 || rlDie "failed to start readltime-virtual-host"
			rlRun "touch reboot_1423560"
			grubby --info DEFAULT
			rhts-reboot
		rlPhaseEnd
	else
		rlPhaseStartSetup
			mount | grep debug || mount -t debugfs dd /sys/kernel/debug
			rlRun "source_compile"
			if ((trace)); then
				rlRun "echo nop > $tracing_dir/current_tracer"
				rlRun "echo 1 > $tracing_dir/events/sched/sched_switch/enable"
				rlRun "echo 1 > $tracing_dir/events/workqueue/enable"
				rlRun "echo 1 > $tracing_dir/events/timer/timer_expire_entry/enable"
			fi
		rlPhaseEnd

		rlPhaseStartTest
			rlRun "grep nohz_full /proc/cmdline"
			if [ $? -ne 0 ]; then
				report_result "nohz_full_setup" FAIL
				cleanup
				rlRun "touch reboot_1423560_2"
				rhts-reboot
			fi
			rlRun "taskset -pc 0-1 $$"
			# It now needs 2 on each cpu.
			for processor in $(seq 2 $max); do
				rlLogInfo "taskset -c $processor chrt -r 1 stress -c 1"
				taskset -c $processor chrt -r 1 stress -c 1 &
			done
			for processor in $(seq 2 $max); do
				rlLogInfo "taskset -c $processor chrt -r 1 stress -c 1"
				taskset -c $processor chrt -r 1 stress -c 1 &
			done
			rlLogInfo "taskset -c 0-1 sh watch.sh"
			taskset -c 0-1 sh watch.sh | tee -a $OUTPUTFILE
			for log in $(seq 2 $max); do
				rlFileSubmit cpu$log
			done
			rlFileSubmit ps_new.log
		rlPhaseEnd

		rlPhaseStartCleanup
			if uname -r | grep -Eq "x86_64|aarch64"; then
				cleanup
			fi

			rlRun "touch reboot_1423560_2"
			rhts-reboot
		rlPhaseEnd
	fi
rlJournalEnd
rlJournalPrintText

