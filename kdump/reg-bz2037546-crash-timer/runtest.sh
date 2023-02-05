#!/bin/bash
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#  Author: Boluo Ge   <bge@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2037546 - The crash “timer -r” command does not print all the per-CPU clocks in RHEL 8.
# Fixed in RHEL-8.6 crash-7.3.1-5.el8
CheckSkipTest crash 7.3.1-5.el8 && Report

CrashTimerCheck() {
	PrepareCrash

	cat <<EOF >"crash.timer.cmd"
hrtimer_cpu_base.clock_base
timer -r -C 0
exit
EOF

	crash -i crash.timer.cmd > "crash.timer.log"
	local ret=$?
	RhtsSubmit "$(pwd)/crash.timer.cmd"
	RhtsSubmit "$(pwd)/crash.timer.log"
	if [[ "$ret" -ne "0" ]];then
		Error "Failed to run crash command. Please check crash.timer.log"
		return
	fi


	# Before the fix, timer returns only the first 3 clocks
	# e.g.
	# crash> timer -r -C 0
	# CPU: 11  HRTIMER_CPU_BASE: ffff8f829f95ee00
	#   CLOCK: 0  HRTIMER_CLOCK_BASE: ffff8f829f95ee80  [ktime_get]
	#   (empty)

	#   CLOCK: 1  HRTIMER_CLOCK_BASE: ffff8f829f95ef00  [ktime_get_real]
	#   (empty)

	#   CLOCK: 2  HRTIMER_CLOCK_BASE: ffff8f829f95ef80  [ktime_get_boottime]
	#   (empty)
	# crash>

	# After the fix, timer print all 8 clocks
	# e.g.
	# crash> timer -r -C 0
	# CPU: 11  HRTIMER_CPU_BASE: ffff9a775f95ee00
	#   CLOCK: 0  HRTIMER_CLOCK_BASE: ffff9a775f95ee80  [ktime_get]
	#   (empty)

	#   CLOCK: 1  HRTIMER_CLOCK_BASE: ffff9a775f95ef00  [ktime_get_real]
	#   (empty)
	#   ...

	#   CLOCK: 7  HRTIMER_CLOCK_BASE: ffff9a775f95f200  [ktime_get_clocktai]
	#   (empty)
	#  crash>

	# Get length of clock_base array
	local exp=$(cat crash.timer.log | grep -o 'clock_base\[[0-9]\+\]' | grep -o '[0-9]\+')
	# Get the number of Clock that command "timer" prints
	local act=$(cat crash.timer.log | grep "CLOCK:" | wc -l)

	if [[ "$exp" -ne "$act" ]];then
		Error "Failed. Expect to print $exp clocks, but it print $act. Please check crash.timer.log"
	else
		Log "Pass. Crash timer command print $act clocks."
	fi
}

#-------- Start Test --------
Multihost CrashTimerCheck
