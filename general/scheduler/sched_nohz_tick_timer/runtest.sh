#!/bin/bash
# shellcheck disable=SC1090,SC2207,SC2048,SC2034
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

. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../include/runtest.sh

#trap 'Cleanup' SIGHUP SIGINT SIGQUIT SIGTERM SIGUSR1

CASE_LIST=${CASE_LIST:-}
SKIP_CASE=${SKIP_CASE:-}

tracing_dir=/sys/kernel/debug/tracing
nr_cpu=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)
max=$((nr_cpu - 1))

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
				rstrnt-report-result "${t}-${reg}" SKIP
				continue
			fi
			if [ -n "$CASE_LIST" ] && ! echo "$CASE_LIST" | grep -q "$reg"; then
				echo "SKIP test $t-$reg"
				rstrnt-report-result "${t}-${reg}" SKIP
				continue
			fi
			pushd "$reg"
			rlPhaseStartTest "${t}-${reg}"
				echo "running: $reg"
				source "${reg}.sh"
				rlRun "$reg"
				rlLog "Sleeping for ${RUN_TIME}s"
				sleep $RUN_TIME
				[ "$(type -t "${reg}_cleanup")" = "function" ] && rlRun "${reg}_cleanup" || rlLogInfo "WARN: ${reg}_cleanup is not defined or failed"
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
	grubby --info DEFAULT | grep "$grep_param" && rstrnt-report-result nohz_cleanp FAIL
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

# every processor list from lscpu, reserve $hkeeper_per_range cpus for housekeeping, isolate all other cpus.
# for a 2 sockets 36 cores machine as below, reserve 4 processors(threads) per range
#NUMA node0 CPU(s):   0-35,72-107
#NUMA node1 CPU(s):   36-71,108-143
#[root@intel-whitley-02 topology]# get_isolated_list 4
#4-35,76-107,40-71,112-143

# for the below cpu:
#NUMA node0 CPU(s):   0,8,16,24,32,40,48,56
#NUMA node1 CPU(s):   2,10,18,26,34,42,50,58
#NUMA node2 CPU(s):   4,12,20,28,36,44,52,60
#NUMA node3 CPU(s):   6,14,22,30,38,46,54,62
#NUMA node4 CPU(s):   1,9,17,25,33,41,49,57
#NUMA node5 CPU(s):   3,11,19,27,35,43,51,59
#NUMA node6 CPU(s):   5,13,21,29,37,45,53,61
#NUMA node7 CPU(s):   7,15,23,31,39,47,55,63
#[root@dell-per7425-01 ~]# get_isolated_list 4
#32,40,48,56,34,42,50,58,36,44,52,60,38,46,54,62,33,41,49,57,35,43,51,59,37,45,53,61,39,47,55,63

function get_isolated_list()
{
	local hkeeper_per_range=${1:-2}
	local reverse=${2:-0}
	local range
	local cpu_ranges=($(lscpu | awk -F: -v ORS=" " '/NUMA node.*CPU\(s\).*[0-9]/{gsub(" ","",$0);if ($0 ~ "[0-9]+-[0-9]+") gsub(","," ",$0);print $2}'))

	awk -v nkeeper="$hkeeper_per_range" -v reverse=$reverse -v output="" -v output_reverse="" '
	{	if ($0 ~ "[0-9]+-[0-9]+") {
			split($0, a, "-");
			if (a[2] == "") {
				a[2]=a[1]
			}
			ncpu=a[2]-a[1]+1
			if (nkeeper >=ncpu)
				nkeeper=ncpu-1
			low=a[1]+nkeeper
			if (low >a[2])
				low=a[2]
			output=output""low"-"a[2]","
			high=low-1
			if (high >= a[1])
				output_reverse=output_reverse""a[1]"-"high" "
		} else if ($0 ~ ",") {
			ncpu=split($0,a,",")
			if (nkeeper >= ncpu)
				nkeeper=ncpu-1
			low_index=nkeeper+1
			for (i=low_index; i<ncpu+1; i++) {
				output=output""a[i]","
			}
			for (i=1; i<nkeeper+1; i++)
				output_reverse=output_reverse""a[i]","
		} else {
			output=$0
		}
	}
	END {
		gsub(",$","",output)
		gsub(",$","",output_reverse)
		if (reverse)
			print output_reverse
		else
			print output
	}' <<< $(for range in ${cpu_ranges[*]}; do echo $range; done)
}

# 0-31, would be bit hex mask, such as cpu31: 80000000
# 32-, would be bit hex mask, and shift with ",00000000" such as:
# cpu33: 2,00000000
# cpu64: 1,00000000,00000000
function get_cpu_mask()
{
	local cpu=${1:-48}
	local group=$((cpu / 32))
	local cpu_round=$((cpu % 32))
	local mask_str=$(printf "%x" $((1 << cpu_round)))

	for ((i=0; i<group; i++)); do
		mask_str+=",00000000"
	done

	echo $mask_str
}

if ((nr_cpu <=4)); then
	isolated_cpus=$max
else
	isolated_cpus=$(get_isolated_list 4)
fi

first_isolated=$(echo $isolated_cpus | grep -Eo "^[0-9]+")
last_isolated=$(echo $isolated_cpus | grep -Eo "[0-9]+$")
mask=$(get_cpu_mask $first_isolated)

cfg_file=/etc/tuned/realtime-virtual-host-variables.conf
save_cfg_file=/mnt/save_cfg_nohz_tick_timer

rlJournalStart
	if test -f reboot_1392539_2;  then
		rlPhaseStartTest
			rlRun -l "lscpu"
			rlRun "grep nohz_full /proc/cmdline" 1-255
			rlRun "grep isolcpus /proc/cmdline" 1-255
			rlLog "Test finished, removed nohz kernel parameters."
			nohz_check_commandline
			rm -f reboot_1392539_2 reboot_1392539
		rlPhaseEnd
	elif ! test -f reboot_1392539; then
		rlPhaseStartSetup
			rlRun -l "lscpu"
			if ((nr_cpu < 2)) || ! uname -r | grep -q x86_64; then
				rstrnt-report-result "skip_cpu_$nr_cpu" SKIP
				rlPhaseEnd
				rlJournalEnd
				exit 0
			fi
			active=$(tuned-adm active | awk '{print $NF}')
			echo "$active" | grep 'No current active profile' && active=""
			echo "$active" > reboot_1392539
			rlLogInfo "active tuned profile: $active: $(tuned-adm active)"
			rpm -q tuned || rlRun "yum -y install tuned"
			if rlIsRHEL ">=8.4"; then
				rpm -q stalld || rlRun "yum -y install stalld"
			fi
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
			rstrnt-reboot
		rlPhaseEnd
		rlPhaseStartCleanup
		rlPhaseEnd
	else
		rlPhaseStartSetup
			rlRun -l "lscpu"
			if ((nr_cpu < 2)); then
				rstrnt-report-result "skip_cpu_$(nr_cpu)" SKIP
				rlPhaseEnd
				rlJournalEnd
				exit 0
			fi
			echo isolated_cpus=$isolated_cpus
			mount | grep debug || mount -t debugfs dd /sys/kernel/debug
			pushd ../../include/scripts/
			which stress-ng &>/dev/null && echo "$(which stress-ng) already installed, skip build" || rlRun "sh stress.sh"
			popd

			export tick_symb="tick_sched_handle"
			# the symbol tick_sched_handle is optimized (inclined) during compilation time and not available in tracers
			rlIsRHEL ">=10" && export tick_symb="tick_nohz_handler"

			rlRun "echo nop > $tracing_dir/current_tracer"
			rlRun "echo 2 > $tracing_dir/tracing_cpumask"
			rlRun "echo 1 > $tracing_dir/events/sched/sched_switch/enable"
			rlRun "echo 1 > $tracing_dir/events/workqueue/enable"
			rlRun "echo 1 > $tracing_dir/events/timer/timer_expire_entry/enable"
			rlRun "echo $mask > $tracing_dir/tracing_cpumask"
			rlRun "echo $tick_symb >> $tracing_dir/set_ftrace_filter"
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
			rstrnt-reboot
		rlPhaseEnd
	fi
rlJournalEnd
rlJournalPrintText

