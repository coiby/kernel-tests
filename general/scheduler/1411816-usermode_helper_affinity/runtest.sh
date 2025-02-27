#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/usermode_helper_affinity
#   Description: user mode helper affinity verification.
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

. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../include/runtest.sh

rlJournalStart
	rlPhaseStartSetup
		check_cgroup_version

		kver_major=$(uname -r | cut -d- -f1 | cut -d. -f 1) # 3
		kver_minor=$(uname -r | cut -d- -f1 | cut -d. -f 2) # 10
		phasename="Test ${FUNCNAME[0]}"

		# From 4.3, the __call_usermodehelper is dropped and renamed to
		# call_usermodehelper_exec_async with commit :
		# b6b50a814d0ece9c1f98f2b3b5c2a251a5c9a211
		if ((kver_major == 4)) && ((kver_minor > 10)) || ((kver_major > 4)); then
			trace_func=call_usermodehelper_exec_async
		else
			trace_func=__call_usermodehelper
		fi
	rlPhaseEnd

	rlPhaseStartTest $phasename
		! test -f /sys/devices/virtual/workqueue/cpumask && \
			rstrnt-report-result "SKIPPED_UNSUPPORTED" SKIP && exit 0
		rlRun "echo 1 > /sys/devices/virtual/workqueue/cpumask"

		mount | grep debugfs || mount -t debugfs d /sys/kernel/debug
		! grep function /sys/kernel/debug/tracing/available_tracers && \
			rstrnt-report-result "SKIPPED_UNSUPPORTED" SKIP && exit 0

		FILTER=/sys/kernel/debug/tracing/set_ftrace_filter
		rlRun "echo $trace_func >  $FILTER"
		rlRun "echo function > /sys/kernel/debug/tracing/current_tracer"
		runner=./start_helper.sh
		[ "$CGROUP_VERSION" != 1 ] && runner=./start_helper_cgroupv2.sh
		for _ in $(seq 1 10); do
			rlRun "$runner"
		done
		TRACE=/sys/kernel/debug/tracing/trace
		set -o pipefail
		rlRun "grep call_user $TRACE | grep -E '\[.*\]' -o | grep -v \"000\"" 1-255
		set +o pipefail
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "echo nop > /sys/kernel/debug/tracing/current_tracer"
	rlPhaseEnd

rlJournalEnd
rlJournalPrintText

