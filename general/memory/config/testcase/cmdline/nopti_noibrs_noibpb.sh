#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: disable spectre and meltdown to see what happen.
#   Author: chuhu@redhat.com
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

function nopti_noibrs_noibpb()
{

	if ! test -f /mnt/nopti_init; then
		touch /mnt/nopti_init

		rlAssertNotGrep "nopti" /proc/cmdline
		rlAssertNotGrep "noibpb" /proc/cmdline
		rlAssertNotGrep "noibrs" /proc/cmdline

		rlRun "yum -y install perf" 0-255
		rlRun "perf bench sched messaging -l 10" -l 0-255
		rlRun "perf bench mem memcpy -l 1000" -l 0-255
	fi

	ibpb_support="$(grep ibpb_support /proc/cpuinfo)"
	spec_ctrl="$(grep spec_ctrl /proc/cpuinfo)"

	setup_cmdline_args "nopti noibrs noibpb"

	rlAssertGrep "nopti" /proc/cmdline
	rlAssertGrep "noibpb" /proc/cmdline
	rlAssertGrep "noibrs" /proc/cmdline

	rlRun "perf bench sched messaging -l 10" -l 0-255
	rlRun "perf bench mem memcpy -l 1000" -l 0-255

	if uname -m | grep -q x86 && test -f /sys/kernel/debug/x86/ibrs_enabled; then
		rlRun "cat /sys/kernel/debug/x86/pti_enabled" -l
		rlRun "cat /sys/kernel/debug/x86/ibrs_enabled" -l
		rlRun "cat /sys/kernel/debug/x86/ibpb_enabled" -l
		rlAssertEquals "pti_enabled should be 0"   "$(cat /sys/kernel/debug/x86/pti_enabled)"  0
		rlAssertEquals "ibrs_enabled should be 0"  "$(cat /sys/kernel/debug/x86/ibrs_enabled)"  0
		rlLog "noibpb is depreted.."

		# Reenable the pit and others.
		rlRun "echo 1 > /sys/kernel/debug/x86/pti_enabled" -l 0
		rlAssertEquals "pti_enabled should be 1"   "$(cat /sys/kernel/debug/x86/pti_enabled)"  1

		if [ -n "$spec_ctrl" -a -n "$ibpb_enabled" ]; then
			rlRun "echo 1 > /sys/kernel/debug/x86/ibrs_enabled" -l 0
			rlRun "echo 1 > /sys/kernel/debug/x86/ibpb_enabled" -l 0
			rlAssertEquals "ibrs_enabled should be 1"  "$(cat /sys/kernel/debug/x86/ibrs_enabled)" 1
			rlAssertEquals "ibpb_enabled should be 1"  "$(cat /sys/kernel/debug/x86/ibpb_enabled)" 1
		fi

		# Run a perf mm sanity check
		rlRun "perf bench sched messaging -l 10" -l 0-255
		rlRun "perf bench mem memcpy -l 1000" -l 0-255

	fi
	cleanup_cmdline_args "nopti noibrs noibpb"
}
