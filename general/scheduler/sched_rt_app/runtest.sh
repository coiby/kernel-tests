#!/bin/bash
# shellcheck disable=SC1090
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/sched_policy_prio
#   Description: deadline scheduler class
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
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

# Enable TMT testing for RHIVOS
auto_include=../../../automotive/include/rhivos.sh
[ -f $auto_include ] && . $auto_include
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0
declare -F check_result && report_func=check_result || report_func=rstrnt-report-result

. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../include/lib.sh
. ../include/runtest.sh || exit 1

check_cgroup_version

if test -f /sys/kernel/debug/sched/features; then
	sched_feature_file="/sys/kernel/debug/sched/features"
elif test -f /sys/kernel/debug/sched_features; then
	sched_feature_file="/sys/kernel/debug/sched_features"
fi

# when runtime share is enabled, cpu * bw can be used by the process,
# max is 1.
old_rt_runtime_share=2
function setup_runtime_share()
{
	local action=${1}

	if [ "$CGROUP_VERSION" = 2 ]; then
		echo "cgroup v2 don't support rt_runtime_share"
		return
	fi

	grep -w NO_RT_RUNTIME_SHARE $sched_feature_file && old_rt_runtime_share=0
	grep -w RT_RUNTIME_SHARE $sched_feature_file && old_rt_runtime_share=1

	if [ $old_rt_runtime_share = 1 ]; then
		rlLog "RT_RUNTIME_SHARE is enabled by default"
	elif [ $old_rt_runtime_share = 0 ]; then
		rlLog "RT_RUNTIME_SHARE is disabled by default"
	else
		rlLogWarning "no sched feature for RT_RUNTIME_SHARE!"
	fi

	if [ "$action" -eq  1 ]; then
		echo RT_RUNTIME_SHARE > $sched_feature_file
	else
		echo NO_RT_RUNTIME_SHARE > $sched_feature_file
	fi
}

function restore_runtime_share()
{
	if [ $old_rt_runtime_share = 1 ]; then
		rlLog "Restore/enable RT_RUNTIME_SHARE"
		echo RT_RUNTIME_SHARE > $sched_feature_file
	elif [ $old_rt_runtime_share = 0 ]; then
		rlLog "Restore/disable RT_RUNTIME_SHARE"
		echo NO_RT_RUNTIME_SHARE > $sched_feature_file
	else
		rlLogInfo "No old_setting for RT_RUNTIME_SHARE."
	fi
}
# Cgroup runtime setup helper. for rr and fifo, bw can be controlled
# by cgruop rt_runtime_us.
function setup_rt_cgroup_bw()
{
	# 0.8 means it run on once cpu, with 80% running and 20% idle.
	# but when NO_RT_RUNTIME_SHARE. This value is real bandwidth.
	local bandwidth_one_cpu=${1}
	local group=${3:-cpu:/rtbw}

	# get system.slice/rtbw from cpu:/system.slice/rtbw
	local group_dir=$(echo $group | awk -F: '{gsub("^/|/$","",$2); print $2}')

	local rt_period_current=$(cgroup_get $group_dir cpu cpu.rt_period_us)
	# in us unit
	local rt_period_target=${2:-$rt_period_current}
	local rt_runtime_target=$(echo $rt_period_target \* $bandwidth_one_cpu | bc | cut -d. -f1)

	# If we don't support rt group schedule, don't setup to get false positive.
	((RT_GROUP_SCHED)) || return 0

	if [ -z "$bandwidth_one_cpu" ] || [ "$(echo $bandwidth_one_cpu \> 1 | bc)" = "1" ]; then
		rlLogWarning "Failed, target rt_runtime($rt_runtime_target) is greater than rt_period($rt_period_current)"
		return 1
	fi

	echo "${FUNCNAME[0]}: before set: checking cgroup hierachy"
	systemd-cgls | tee cgroups.txt
	echo "${FUNCNAME[0]}: before set: checking cgroup hierachy end ."

	rlRun "cgroup_get $group_dir cpu" -l 0 "current rt cgroup config"
	rlRun "cgroup_set $group_dir cpu cpu.rt_period_us=$rt_period_target cpu.rt_runtime_us=$rt_runtime_target" -l 0 "set period/runtime"
	rlRun "cgroup_get $group_dir cpu cpu.rt_runtime_us,cpu.rt_period_us 1" -l 0 "new runtime"

	echo "${FUNCNAME[0]} after set: checking cgroup hierachy"
	systemd-cgls | tee cgroups.txt
	echo "${FUNCNAME[0]} after set: checking cgroup hierachy end ."

	local rt_runtime_new=$(cgroup_get $group_dir cpu cpu.rt_runtime_us)
	if [ "$rt_runtime_new" != "$rt_runtime_target" ]; then
		rlLogWarning "Failed, expect rt_runtime to $rt_runtime_target, but got $rt_runtime_new"
		rlLogInfo "bandwidth for cgroup $group:"
		rlRun "cgroup_get $group_dir cpu" -l 0-255
		return 1
	else
		rlLogInfo "bandwidth for cgroup $group:"
		rlRun "cgroup_get $group_dir cpu" -l 0-255
	fi
	return 0
}

function setup_cpu_affinity()
{
	local nr_available=$(nproc)
	local nr_present=$(nproc --all)
	local isolated=$(cat /sys/devices/system/cpu/isolated)

	if ! grep -q isolcpus /proc/cmdline || ! uname -r | grep -q rt; then
		# cpu isolation not enabled or not running a rt kernel
		sed "/cpulist_placeholder/d" -i config/*.json
		return
	elif (( nr_available <= 2 )) && (( nr_present > nr_available )); then
		# cpu isolation enabled and running a rt kernel and so few cores
		# left for housekeeping
		rlLog "using cpu affinity in the rt-app config files"
		rlLog "nr_available: $nr_available, nr_present: $nr_present, isolated: $isolated"
		for sublist in $(echo $isolated | tr ',' ' '); do
			cpulist+=",$(seq -s ',' $(echo $sublist | tr '-' ' '))"
		done
		sed "s/cpulist_placeholder/${cpulist:1}/g" -i config/*.json
		rlLog "using isolated cpulist: $cpulist"
		rlRun "grep -n cpus config/*.json"
		cpu_affinity="--taskset ${isolated}"
	else
		# cpu isolation enabled and running a rt kernel and more than 2
		# cores are available for scheduling
		sed "/cpulist_placeholder/d" -i config/*.json
	fi
}

function test_setup()
{
	if ! (($is_rhivos)); then
		# rhel9.0
		yum -y install cmake autoconf gcc libgcc gcc-c++ m4 libtool git bzip2

		../../include/scripts/buildroot.sh json-c-devel json-c
		rpm -q util-linux || yum -y install util-linux
	fi

	rlAssertRpm  util-linux || rlDie "util-linux is needed for change policy of rt"

	# Install stress-ng, which is hacked to support deadline sched policy.
	if ! (($is_rhivos)); then
		stress_ng_install && have_stress_ng=1
	fi

	stress_enabled_deadline=$(stress-ng --sched ? 2>&1| grep -wo deadline)

	# These would be overrided in set_hierachy
	select_cgp="cpu:/rtbw"
	select_cgp_other="cpu:/rtbw_other"
	cg_dir=""
	cg_controller=""

	# rhel9 and fedora, the process name is stress-ng not stress-ng-cpu
	rpm -qf $(which stress-ng) && proc_name=stress-ng
	echo proc_name=$proc_name
	if [ "$CGROUP_VERSION" != 2 ]; then
		true
	else
		echo "Skip installing libcgroup-tools as running cgroup v2"
	fi

	if ! (($is_rhivos)); then
		rlIsRHEL ">=9" && sched_feature_file="/sys/kernel/debug/sched/features"
	else
		sched_feature_file="/sys/kernel/debug/sched/features"
	fi

	uname -r | grep -q rt && load_limit=${load_limit:-"-l 95"}

	echo "Before test: "
	systemd-cgls | tee cgroups.txt
	echo "=============================================="
	rlFileSubmit "cgroups.txt"

	if uname -r | grep rt && virt-what | grep kvm; then
		$report_func skip_kernel_rt_kvm_guest_${SCHED_NR_CPU} SKIP
		exit 0
	fi

	SCHED_NR_CPU=$(nproc)
	if [ $SCHED_NR_CPU -lt 1 ]; then
		$report_func test_skip_nr_cpu_${SCHED_NR_CPU} SKIP
		return
	fi

	if stat /run/ostree-booted > /dev/null 2>&1; then
		local kernel_config=/usr/lib/ostree-boot/config-$(uname -r)
	else
		local kernel_config=/boot/config-$(uname -r)
	fi

	if grep CONFIG_RT_GROUP_SCHED=y $kernel_config; then
		RT_GROUP_SCHED=1
		rlLogInfo "RT_GROUP_SCHED enabled..."
	else
		RT_GROUP_SCHED=0
		rlLogInfo "RT_GROUP_SCHED not enabled..."
	fi

	local pkg=rt-app.20210311.tgz
	local folder=rt-app.20210311
	[ -z "$LOOKASIDE" ] && LOOKASIDE=http://download.devel.redhat.com/qa/rhts/lookaside/
	if curl -LkO  $LOOKASIDE/$pkg; then
		tar -zxf $pkg
	else
		rlRun "git clone --depth 1 https://gitlab.com/redhat/centos-stream/tests/kernel/core/rt-app.git"
		folder=rt-app
	fi

	rlRun "pushd $folder" || rlDie "rt-app failed to download"

	rlRun "autoreconf --install &> autoreconf.log"
	rlRun "./configure --with-deadline &> configure.log" ||
	{ test -f configure.log && cat configure.log; }
	rlRun "make 2>&1 > make.log" || { test -f make.log && cat make.log; rlDie; }
	rlRun "make install" || rlDie "rt-app installtion"
	rlRun "popd"

	mkdir fifo rr deadline

	# For band width control of fifo and rr. dln can't be controlled by cgroup
	# currently.

	cgroup_populate_rt_hierachy
	cgroup_create "$(echo $select_cgp | awk -F: '{print $2}')" cpu
	cgroup_create "$(echo $select_cgp_other | awk -F: '{print $2}')" cpu

	echo "checking cgroup hierachy start ..."
	systemd-cgls | tee cgroups.txt
	echo "checking cgroup hierachy end ..."

	setup_cpu_affinity
}


function calc_sched_rt_bw()
{
	local policy=$1
	local comm=${2:-rt-app}
	local duration=${3:-30}
	local interval=3
	# unexpected thread appeared in statistics, caused by incomplete cleanups.
	# this is for debug as cpu usage is higher than shown with the intended policy/command.
	# local wild=""

	match=0
	old_match=0
	pcpu_new=0.0

	duration=$((duration / interval))

	rlLogInfo "checking policy ($policy) for $comm ..."
	for i in $(seq 1 $duration); do
		ps -L -C "$comm" -o pid,pcpu,tid,cls,comm | egrep "$policy" && ((match++))
		# check bandwidth control
		if ((match > old_match)); then
			if [ $((i % 10)) = 1 ]; then
				rlLogInfo "checking policy ($policy) for $comm ..."
				rlRun "ps -L -C $comm -o pid,pcpu,tid,cls,comm | egrep '$policy'" 0-255
			fi
			pcpu_new=$(ps -L -C "$comm" -o pid,pcpu,cls,args  | awk 'BEGIN{a=0.0}/'$policy'/{a=a+$2}END{printf "%0.2f", a}')
			echo pcpu_new $pcpu_new
		else
			# $comm has already ended.
			if ((match)); then
				break
			fi
		fi
		old_match=$match
		sleep $interval
	done
}

# check bandwidth
function check_sched_rt_bw()
{
	if [ "$match" = "" ] || [ "$match" = "0" ]; then
		rlFail "bandwidth check failed (no matched policy)"
		return 1;
	fi
	((RT_GROUP_SCHED)) || return
	local average=${pcpu_new}
	echo aveage : $average, match $match
	# according to deadline.json, the bandwidth is 0.5
	local right_min=$1
	local right_max=$2
	local assert1=$(echo $right_min \< $average | bc)
	local assert2=$(echo $right_max \> $average | bc)

	#known issue on x86_64: "bzdeadline:bz1868611"
	if rlIsRHEL ">=8.3" && uname -m | grep x86_64 -q; then
		if [ "$(echo $average \> $right_min | bc)" = "1" ] && [ "$(echo $average \< $right_max | bc)" = "1" ]; then
			true
		else
			rlReport bzdeadline:unfix-bz1868611 WARN 10
		fi
	else
		rlAssertEquals "$average should greater than $right_min" "$assert1" 1
		rlAssertEquals "$average should smaller than $right_max" "$assert2" 1
	fi
}

function test_sched_rr()
{
	if [ "$CGROUP_VERSION" = 2 ]; then
		echo "not supported cgroup v2"
		$report_func "sched_rr" SKIP
		return
	fi

	rlPhaseStartTest sched_rr
		rlLogInfo "Test schedule rt class (RR policy)"
		# rt-app section, dance ..
		rlRun "rt-app config/rr.json &"
		pid=$!
		sleep 10

		calc_sched_rt_bw RR rt-app 120
		rlLogWarning "This is not real bandwidth control, please use cgroup!"
		wait

		# new stage. execute stress-ng and cgexec for testing
		if [ ! "$have_stress_ng" = 1 ]; then
			rlPhaseEnd
			return
		fi
		setup_rt_cgroup_bw 0.7 100000 $select_cgp
		rlRun "cgexec.sh $cg_dir $cg_controller stress-ng $cpu_affinity --sched rr --vm 1 $load_limit -t 130 &"
		calc_sched_rt_bw RR "stress-ng-vm" "120"
		# rt bandwidth control is so coarse, we make it 30% tolerence.
		check_sched_rt_bw 55.0 85.0
		pkill -9 -f stress-ng
	rlPhaseEnd
}

#bug1344565  Enable SCHED_DEADLINE to RHEL7.x
function test_sched_deadline()
{
	#------------------------ DEADLINE -------------------------------
	rlPhaseStartTest sched_deadline

		dump_cgroup_info $$

		# rt-app section, dance ..
		rlRun "rt-app config/deadline.json &"

		rlRun "sleep 10"
		calc_sched_rt_bw '#6|DLN' "rt-app" 120
		wait

		if [ -z "$stress_enabled_deadline" ]; then
			rlLogWarning "stress-ng is not successfully patched!!!"
			return
		fi

		rlRun "stress-ng $cpu_affinity --sched deadline  --sched-period 1000000000 --sched-runtime 200000000 --sched-deadline 1000000000 --cpu 1 $load_limit -t 120 &"
		calc_sched_rt_bw '#6|DLN' "${proc_name:-stress-ng-cpu}" 120
		check_sched_rt_bw 18.0 22.0
		pkill -9 -f stress-ng

	rlPhaseEnd
}

function test_sched_fifo()
{
	if [ "$CGROUP_VERSION" = 2 ]; then
		echo "not supported cgroup v2"
		$report_func "sched_fifo" SKIP
		return
	fi

	rlPhaseStartTest sched_fifo

		dump_cgroup_info $$

		rlRun "rt-app config/fifo.json &"
		pid=$!
		rlRun "sleep 10"

		calc_sched_rt_bw FF "rt-app" 120
		rlLogWarning "This is not real bandwidth control, please use cgroup!"
		rlRun -l "top -H -n 1" 0-255
		wait
		if ps -p $pid -o args | grep rt-app; then
			kill $pid
		fi

		if [ ! "$have_stress_ng" = "1" ]; then
			rlPhaseEnd
			return
		fi
		# execute stress-ng and cgexec for testing
		setup_rt_cgroup_bw 0.4 100000 $select_cgp
		rlRun "cgexec.sh $cg_dir $cg_controller stress-ng $cpu_affinity --sched fifo --vm 1 $load_limit -t 130 &"
		calc_sched_rt_bw FF "${proc_name:-stress-ng-vm}" "120"
		check_sched_rt_bw 25.0 55.0
		pkill -9 -f stress-ng

	rlPhaseEnd
}

function test_sched_rt()
{
	pid=
	match=0
	old_match=0
	pcpu_new=0.0

	setup_runtime_share 0
	if ! uname -r | grep -q s390x; then
		test_sched_rr
		test_sched_deadline
		test_sched_fifo
	else

		uname -r | grep -q s390x && rlLogInfo "Skip test ${FUNCNAME[0]} on s390x ..." && return
	fi
	restore_runtime_share
}

# Run test with RUN_TIME_SHARE enabled.
function test_rt_runtime_share()
{
	uname -r | grep -q s390x && rlLogInfo "Skip test ${FUNCNAME[0]} on s390x ..." && return

	if [ "$CGROUP_VERSION" = 2 ]; then
		$report_func "rt_runtime_not_support" SKIP
		return
	fi

	rlPhaseStartTest rt_runtime_share
		setup_runtime_share 1
		# in rt-app config, we have two threads, and we'll have 2% cpu time for each
		# rt_rq with cgroup limit
		local pcpu_usage=0.02
		# 15% tolerence
		local expect_cpu_usage=$(printf "%.2f\n" $(echo $SCHED_NR_CPU \* $pcpu_usage \* 100| bc))
		if [ "$(echo $expect_cpu_usage \> 200 | bc)" = 1 ]; then
			expect_cpu_usage=200
		fi
		local expect_cpu_min=$(printf "%.2f\n" $(echo $expect_cpu_usage \* 0.85 | bc))
		local expect_cpu_max=$(printf "%.2f\n" $(echo $expect_cpu_usage \* 1.15 | bc))
		rlLogInfo "nr_cpus=${SCHED_NR_CPU},expect_cpu_usage=$expect_cpu_usage"

		setup_rt_cgroup_bw $pcpu_usage 100000 $select_cgp

		# This is a 2 threads process, will consumte 200% cpu if no limit.
		# but with cgroup limit, it will get (0.1 * nr_cpu) cpu usage.
		rlRun "cgexec.sh $cg_dir $cg_controller rt-app ./config/rt_runtime_share.json &"
		calc_sched_rt_bw RR rt-app 120
		check_sched_rt_bw $expect_cpu_min $expect_cpu_max
		wait
		restore_runtime_share
	rlPhaseEnd
}

function test_cleanup()
{
	if [ "$CGROUP_VERSION" = "1" ]; then
		cgroup_destroy $cg_dir cpu
		cg_dir="$(echo $select_cgp_other | awk -F: '{print $2}')"
		cgroup_destroy $cg_dir cpu
		cgroup_restore_rt_hierachy

		echo "After test: "
		systemd-cgls | tee -a cgroups_end.txt
		rlFileSubmit cgroups_end.txt
	fi
}

rlJournalStart
	rlPhaseStartSetup
		test_setup
	rlPhaseEnd

	test_sched_rt
	test_rt_runtime_share

	rlPhaseStartCleanup
		test_cleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
