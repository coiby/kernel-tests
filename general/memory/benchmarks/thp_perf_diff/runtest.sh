#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: thp perf diff
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
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
# include beaker environment
. /usr/bin/rhts-environment.sh        || exit 1
. /usr/share/beakerlib/beakerlib.sh   || exit 1


# Threads number
n_proc=$(grep -wc processor /proc/cpuinfo)
NPROC=${NPROC:-$n_proc}

prepare() {
	which sysbench && return
	rlLog "Trying to install sysbench"
	if ../../../include/scripts/sysbench.sh; then
		which sysbench > /dev/null
	else
		return 1
	fi
}

check_thp_support()
{
	! test -d /sys/devices/system/node/node0 && return 1
	! test -f /sys/kernel/mm/transparent_hugepage/enabled && return 1
	return 0
}

check_test_continue()
{
	if test -f TEST_DONE; then
		return 1
	fi
	return 0
}

get_matrix()
{
	hugepage_sizes=($(find /sys/devices/system/node/node0 -name hugepages-* -type d  | awk -F/ '{match($NF, /[0-9]+/, a);print a[0]}'))
	echo hugepage_sizes=${hugepage_sizes[*]}
	if ! test -f HUGEPAGE_SIZES; then
		echo ${hugepage_sizes[*]} | sed "s/ /\n/g" > HUGEPAGE_SIZES
		nr_lines=$(wc -l HUGEPAGE_SIZES | awk '{print $1}')
		default_hpsz=$(awk '/Hugepagesize/ {print $2}' /proc/meminfo)
		echo "Removing default hugepage size: $default_hpsz from list"
		if ((nr_lines > 1)); then
			sed -i '/'$default_hpsz'/d' HUGEPAGE_SIZES
			sed -i '1i'$default_hpsz'' HUGEPAGE_SIZES
		fi
		echo $default_hpsz > DEFAULT_HUGEPAGE
	else
		default_hpsz=$(awk  '/Hugepagesize/ {print $2}' /proc/meminfo)
	fi
	rlLogInfo "Supported hugepage sizes in kB: ${hugepage_sizes[*]}"
	rlLogInfo "Default hugepage sizes in kB: $default_hpsz"
}

pop_hsz()
{
	sed -i '1d' HUGEPAGE_SIZES
}

get_hsz_k()
{
	sed -n '1p' HUGEPAGE_SIZES
}

verify_hpsz()
{
	local actual_size=$(cat /proc/meminfo  | awk '/Hugepagesize:/ {print $2}')
	local sz_expect=$(get_hsz_k)
	[ "$actual_size" = "$sz_expect" ] || rlDie "hugepage size is $actual_size, but expect $sz_expect"
	echo "actual hugepage size: $actual_size"
}

get_hsz_str()
{
	local k=$(get_hsz_k)
	if ((k < 1024)); then
		echo ${k}K
	else
		echo $((k/1024))M
	fi
}

run_benchmark()
{
	local log=${1}
	local ptr=${2}
	rlLog "===== benchmark for thp $log start ============"
	rlRun -l "sysbench --test=memory --num-threads=${NPROC} --memory-total-size=100G run > $log"
	local etime=$(awk -F: '/total time:/ {gsub(" |s$","");print $2}' $log)
	eval ${ptr}=$etime
	echo "$ptr=$etime"
	rlLog "Time cost:"
	rlLog "$log: $etime"
	rlLog "===== benchmark for thp log end  ============"
	rlFileSubmit $log ${log}.txt
}

abort_test()
{
	echo "grubby --remove-args default_hugepagesz --update-kernel DEFAULT"
	grubby --remove-args default_hugepagesz --update-kernel DEFAULT
	grubby --info DEFAULT
	rlDie "$*"
}

# Compare between 'never' and 'always'
run_diff()
{
	local pass_mark=0.2

	cat /proc/meminfo  | grep -i Hugepagesize
	cat /proc/cmdline

	rlPhaseStartTest hugepage-$hsz_str.always
		# Run always
		rlRun "echo always > /sys/kernel/mm/transparent_hugepage/enabled"
		thp_state=$(gawk '{match($0, /\[(.*)\]/, a); print a[1]}' /sys/kernel/mm/transparent_hugepage/enabled)
		rlAssertEquals "should be always" "always" "${thp_state}"
		run_benchmark ${thp_state}_${hpsz} $thp_state
	rlPhaseEnd

	rlPhaseStartTest hugepage-$hsz_str.never
		# Run never
		rlRun "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
		thp_state=$(gawk '{match($0, /\[(.*)\]/, a); print a[1]}' /sys/kernel/mm/transparent_hugepage/enabled)
		rlAssertEquals "should be never" "never" "${thp_state}"
		run_benchmark ${thp_state}_${hpsz} $thp_state
		# always and never are defined with 'eval' in run_benchmark
		# shellcheck disable=SC2154
		diff=$(echo | awk -v always=$always -v never=$never '{print always-never}')
		# always and never are defined with 'eval' in run_benchmark
		# shellcheck disable=SC2154
		diff_percent="$(echo | awk -v diff=$diff -v always=$always -v mark=$pass_mark '{if (diff < 0) diff=-diff;
			diff_pct=diff/always; printf("%s",diff_pct);if (diff_pct > mark) printf (" fail\n");}')"
		rlLog "result diff is always-never=$diff, |diff|/always=$diff_percent"
	rlPhaseEnd

	if echo "$diff_percent" | grep fail; then
		rlReport "thp-$((hpsz * 1024))-perf-diff" FAIL
	else
		rlReport "thp-$((hpsz * 1024))-perf-diff" PASS
	fi
}

run_default()
{
	hpsz=$(cat DEFAULT_HUGEPAGE)
	hsz_str=$(get_hsz_str)

	test -f ${hpsz}_DONE && return
	verify_hpsz
	pop_hsz
	run_diff
	touch ${hpsz}_DONE && return
}

run_matrix()
{
	hpsz=$(get_hsz_k)
	hsz_str=$(get_hsz_str)

	[ -z "$hpsz" ] && return
	if [ ! -f ${hpsz}_REBOOT ]; then
		echo "grubby --args default_hugepagesz=$hsz_str --update-kernel DEFAULT"
		grubby --args default_hugepagesz=$hsz_str --update-kernel DEFAULT
		grubby --info DEFAULT
		touch ${hpsz}_REBOOT
		echo "Rebooting start ..."
		rhts-reboot
	else
		rpm -q bc || yum -y install bc
		verify_hpsz
		pop_hsz
		default_hpsz_cmdline=$(gawk '{match($0, /default_hugepagesz=(.*)/, a);
			gsub("G", "*1024*1024", a[1]); gsub("K", "", a[1]);
			gsub("M", "*1024", a[1]); print a[1]}' /proc/cmdline | bc)
		rlLogInfo "Default hugepage sizes in cmdline kB: $default_hpsz_cmdline"
		rlAssertEquals "default hugepage size should be same with cmdline" "${default_hpsz_cmdline}" "$default_hpsz" || abort_test
		run_diff
		run_matrix
	fi
}

rlJournalStart
	rlPhaseStartSetup
		if prepare; then
			get_matrix
		else
			rlLogInfo "sysbench install failed."
			rstrnt-report-result "$RSTRNT_TASKNAME" SKIP
			exit 0
		fi
	rlPhaseEnd

	if check_thp_support; then
		if check_test_continue; then
			rlPhaseStartTest
				run_default
				run_matrix
			rlPhaseEnd

			rlPhaseStartCleanup
				rlLogInfo "Removing default_hugepagesz from kernel cmdline..."
				grubby --remove-args default_hugepagesz --update-kernel DEFAULT
				grubby --info DEFAULT
				touch TEST_DONE
				rhts-reboot
			rlPhaseEnd
		else
			rlPhaseStartCleanup hugepage-cleanup
				rlLogInfo "default_hugepagesz from kernel cmdline..."
				rlAssertNotGrep default_hugepagesz /proc/cmdline
			rlPhaseEnd
		fi
	else
		rlPhaseStartTest "hugepage-not-support"
		rlPhaseEnd
	fi

rlJournalEnd
rlJournalPrintText


