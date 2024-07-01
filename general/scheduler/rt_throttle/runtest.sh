#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   general/scheduler/rt_throttle
#   Description: verify rt_throttle feature works
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

rlJournalStart
	rlPhaseStartSetup
		rlRun "gcc rt_throttle.c -lpthread -o rt_throttle" || rlDie "failed to compile the test code"
		if test -f /sys/kernel/debug/sched/features; then
			sched_feature_file="/sys/kernel/debug/sched/features"
		elif test -f /sys/kernel/debug/sched_features; then
			sched_feature_file="/sys/kernel/debug/sched_features"
		fi
	rlPhaseEnd

	rlPhaseStartTest
		# make sure RT throttle is not disabled
		rlAssertNotGrep "-1" "/proc/sys/kernel/sched_rt_runtime_us"
		rlRun "grep -o NO_RT_RUNTIME_SHARE $sched_feature_file" 0 \
			"make sure rt runtime share is disabled"
		runtime_share_enabled=$?
		rlRun "./rt_throttle"
		# if rt runtime share is enabled, disable it and re-test, we have already reported
		# failures in the above checks.
		if ((runtime_share_enabled)); then
			rlRun "echo NO_RT_RUNTIME_SHARE > $sched_feature_file" \
				0 "force the runtime share to be disabled"
			rlRun "./rt_throttle"
		fi
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "rm rt_throttle"
		if ((runtime_share_enabled)); then
			rlRun "echo RT_RUNTIME_SHARE > $sched_feature_file"
		fi
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

