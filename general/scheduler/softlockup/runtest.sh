#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   general/scheduler/softlockup
#   Description: verify watchdog detector can detect softlockup
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../../automotive/include/rhivos.sh
declare -F kernel_automotive

# for ostree support
if stat /run/ostree-booted > /dev/null 2>&1; then
	CONFIG=/usr/lib/ostree-boot/config-$(uname -r)
else
	CONFIG=/boot/config-$(uname -r)
fi

TIMEOUT=${TIMEOUT:-60}
SCHED_CLASS=${SCHED_CLASS:-FIFO}
SCHED_PRIORITY=${SCHED_PRIORITY:-1}

TEST_PASS=0

# check dmesg for the softlockup splat
function check_softlockup()
{
	local timeout=$TIMEOUT
	while ((timeout-- > 0)); do
		if dmesg | grep -A 40 -E "watchdog: BUG: soft lockup - CPU#[0-9]+ stuck for [0-9]+s!"; then
			dmesg > test_dmesg.txt
			# escape from the beaker dmesg check plugin
			dmesg -C
			rlPass "softlockup function test pass"
			rlFileSubmit test_dmesg.txt
			rlRun "echo 1 > /sys/module/cpu_hogger/parameters/stop_hogging" 0 "stop the hogger thread"
			return 0
		fi
		sleep 1
	done
	return 1
}

rlJournalStart
	if uname -r | grep s390x; then
		rstrnt-report-result "s390x CONFIG_SOFTLOCKUP_DETECTOR not enabled" SKIP 0
		exit 0
	fi

	rlPhaseStartSetup
		if ! kernel_automotive; then
			kname="$(rpm -qf --qf "%{name}\n" /boot/vmlinuz-$(uname -r) | sed 's/-core//g')"
			kversion="$(rpm -qf --qf "%{version}\n" /boot/vmlinuz-$(uname -r))"
			krelease="$(rpm -qf --qf "%{release}\n" /boot/vmlinuz-$(uname -r))"
			rpm -q "${kname}-devel-${kversion}-${krelease}" || rlRpmInstall "${kname}-devel" "$kversion" "$krelease" "$(uname -m)"
			rpm -q "${kname}-devel-${kversion}-${krelease}" || rlDie "no ${kname}-devel package available"
		else
			install_kernel_automotive_devel || { rstrnt-report-result "${kname}-devel" FAIL; exit 1; }
		fi
	rlPhaseEnd

	rlPhaseStartTest "softlockup detector enabled"
	if ! rlRun "grep 'CONFIG_SOFTLOCKUP_DETECTOR=y' $CONFIG" 0 "check softirq detector is enabled"; then
		rlPhaseEnd
		exit 1
	fi
	rlPhaseEnd

	rlPhaseStartTest "softlockup detector function"
		pushd cpu_hogger
		rlRun "make" 0 "compile the cpu_hogger.ko" || { rstrnt-report-result "compile cpu_hogger.ko" FAIL; exit 1; }
		popd
		loop=3
		dmesg -C
		# if the hogger thread is scheduled onto the same cpu with the ksoftirqd, the timer may be delayed as ksoftirq can't be executed?
		while ((loop-- >0)); do
			rlRun "insmod cpu_hogger/cpu_hogger.ko timeout=$TIMEOUT scheduler_class_str=$SCHED_CLASS sched_priority=$SCHED_PRIORITY preempt_disable_flag=1"
			check_softlockup && TEST_PASS=1 && break
			rmmod cpu_hogger
			# for debug purpose, if this don't happen after a long testing, remove it
			rstrnt-report-result "softlockup detector function" WARN 0
		done
		((TEST_PASS)) || rlFail "softlockup function failed"
	rlPhaseEnd

	rlPhaseStartCleanup
		pushd cpu_hogger
		rlRun "make clean"
		popd
		rmmod cpu_hogger
		rm -f test_dmesg.txt
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

