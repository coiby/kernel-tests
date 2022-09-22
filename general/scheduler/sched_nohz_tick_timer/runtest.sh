#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/1392593
#   Description: timer on nohz cpu check
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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

#trap 'Cleanup' SIGHUP SIGINT SIGQUIT SIGTERM SIGUSR1

CASE_LIST=${CASE_LIST:-}
SKIP_CASE=${SKIP_CASE:-}

tracing_dir=/sys/kernel/debug/tracing
nr_cpu=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)
max=$((nr_cpu - 1))
isolated_cpus="1"
mask=2 #cpu 1

RUN_TIME=1

# Run all subtests in tests folder, in type-bugid pattern
# such as 'ldb_policy-bz1722234'
function run_sub_tests()
{
	local sub_dirs  # case type / scenario
	local sub_dirs2 # bug id or regression type
	local t
	local reg
	local pwd=$(pwd)

	sub_dirs=$(find tests -mindepth 1 -maxdepth 1 -type d -printf "%P\n")
	rlLogInfo "$(pwd): Sub tests: $sub_dirs"
	cd tests
	for t in $sub_dirs; do
		pushd "$t"
		sub_dirs2=$(find . -mindepth 1 -maxdepth 1 -type d -printf "%P\n")
		# bug number or sub type
		for reg in ${sub_dirs2}; do
			if [ -n "$SKIP_CASE" ] && echo "$SKIP_CASE" | grep "$reg"; then
				echo "SKIP test $t-$reg"
				report_result "${t}-${reg}" SKIP
				continue
			fi
			if [ -n "$CASE_LIST" ] && ! echo "$CASE_LIST" | grep -q "$reg"; then
				echo "SKIP test $t-$reg"
				report_result "${t}-${reg}" SKIP
				continue
			fi
			pushd "$reg"
			rlPhaseStartTest "${t}-${reg}"
				echo "running: $reg"
				source "${reg}.sh"
				rlRun "$reg"
				rlLog "Sleeping for ${RUN_TIME}s"
				sleep $RUN_TIME
				type -f "${reg}_cleanup" && rlRun "${reg}_cleanup" || rlLogInfo "WARN: ${reg}_cleanup is not defined or failed"
			rlPhaseEnd
			popd
		done
		popd
	done
	cd "$pwd"
	return
}

nohz_params=" skew_tick isolcpus intel_pstate nosoftlockup tsc nohz nohz_full rcu_nocbs irqaffinity"

function nohz_check_commandline()
{
	local grep_param=${nohz_params// / -e }
	set -x
	cat /proc/cmdline
	grubby --info DEFAULT | grep "$grep_param" && report_result nohz_cleanp FAIL
	set +x
}

function nohz_cleanup_commandline()
{
	for k in $nohz_params; do
		set -x
		grubby --remove-args "$k" --update-kernel DEFAULT
		set +x
	done
}

cfg_file=/etc/tuned/realtime-virtual-host-variables.conf
save_cfg_file=/mnt/save_cfg_nohz_tick_timer

rlJournalStart
	if test -f reboot_1392539_2;  then
		rlPhaseStartTest
			rlRun "grep nohz_full /proc/cmdline" 1-255
			rlRun "grep isolcpus /proc/cmdline" 1-255
			rlLog "Test finished, removed nohz kernel parameters."
			nohz_check_commandline
			rm -f reboot_1392539_2 reboot_1392539
		rlPhaseEnd
	elif ! test -f reboot_1392539; then
		rlPhaseStartSetup
			if ((nr_cpu < 2)) || ! uname -r | grep -q x86_64; then
				report_result "skip_cpu_$nr_cpu" SKIP
				rlPhaseEnd
				rlJournalEnd
				exit 0
			fi
			active=$(tuned-adm active | awk '{print $NF}')
			echo "$active" | grep 'No current active profile' && active=""
			echo "$active" > reboot_1392539
			rlLogInfo "active tuned profile: $active: $(tuned-adm active)"
			rpm -q tuned || rlRun "yum -y install tuned"
			#rlRun "yum -y install tuned-profiles-realtime" 0-255

			yum -y install bcc-tools bcc-devel --enablerepo beaker-CRB
			yum -y install tuned-profiles-nfv-host.noarch
			grep "^isolate_managed_irq=Y" $cfg_file || rlRun "echo \"isolate_managed_irq=Y\" >> $cfg_file"
			grep "^isolated_cores=" $cfg_file
			ln=$(grep -n ^isolated_cores $cfg_file | awk -F: '{print $1; exit}')
			touch $save_cfg_file && echo "$ln" > $save_cfg_file

			# comment out the below line
			# isolated_cores=${f:calc_isolated_cores:1}
			sed -i 's/^isolated_cores=/#&/' $cfg_file
			rlRun "echo \"isolated_cores=$isolated_cpus\" >> $cfg_file"


			rlRun "systemctl start tuned"
			rlRun "tuned-adm profile realtime-virtual-host" 0-255 || rlDie "failed to start readltime-virtual-host"
			rlRun "systemctl restart tuned"
			rlRun "touch reboot_1392539"
			grubby --info DEFAULT
			rhts-reboot
		rlPhaseEnd
		rlPhaseStartCleanup
		rlPhaseEnd
	else
		rlPhaseStartSetup
			if ((nr_cpu < 2)); then
				report_result "skip_cpu_$(nr_cpu)" SKIP
				rlPhaseEnd
				rlJournalEnd
				exit 0
			fi
			mount | grep debug || mount -t debugfs dd /sys/kernel/debug
			pushd ../../include/scripts/
			which stress-ng &>/dev/null && echo "$(which stress-ng) already installed, skip build" || rlRun "sh stress.sh"
			popd

			rlRun "echo nop > $tracing_dir/current_tracer"
			rlRun "echo 2 > $tracing_dir/tracing_cpumask"
			rlRun "echo 1 > $tracing_dir/events/sched/sched_switch/enable"
			rlRun "echo 1 > $tracing_dir/events/workqueue/enable"
			rlRun "echo 1 > $tracing_dir/events/timer/timer_expire_entry/enable"
			rlRun "echo $mask > $tracing_dir/tracing_cpumask"
			rlRun "echo tick_sched_handle >> $tracing_dir/set_ftrace_filter"
			rlRun "echo function > $tracing_dir/current_tracer"
		rlPhaseEnd

		run_sub_tests

		rlPhaseStartCleanup
			rlRun "grubby --remove-args \"nohz=on nohz_full=$isolated_cpus\" --update-kernel DEFAULT"
			rlRun "echo 0 > $tracing_dir/events/enable"
			rlRun "sed -i '/^isolated_cores=/d' $cfg_file" 0-255
			rlRun "sed -i 's/^isolate_managed_irq=.*$/# &/' $cfg_file"

			echo "restoring default isolated_cores parameters"
			test -f $save_cfg_file && ln=$(cat $save_cfg_file)
			[ -n "$ln" ] && sed -i ''$ln's/^#//' "$cfg_file"
			active=$(cat reboot_1392539 | awk -F: '{print $2}')
			if [ "$active" = "" ]; then
				rlRun "tuned-adm off"
			else
				rlRun "tuned-adm profile $active" 0-255
			fi
			rlRun "touch reboot_1392539_2"
			nohz_cleanup_commandline
			nohz_check_commandline
			grubby --info DEFAULT
			test -f $save_cfg_file && rm -f $save_cfg_file
			rhts-reboot
		rlPhaseEnd
	fi
rlJournalEnd
rlJournalPrintText

