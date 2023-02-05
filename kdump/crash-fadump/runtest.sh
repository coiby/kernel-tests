#!/bin/sh
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

# Source Kdump tests common functions.
. ../include/runtest.sh

INITRD_BUILD_WAIT_TIME=${INITRD_BUILD_WAIT_TIME:-30}

# This test requires "fadump=on" to be added to kernel boot cmdline, which has to be
# done before this test.
ConfigFadump() {
    Log "Check if fadump is enabled"
    LogRun "cat /sys/kernel/fadump_enabled" || MajorError "Fadump is not enabled!"
    LogRun "cat /sys/kernel/fadump_registered" || MajorError "Fadump is not registered!"

    # To make sure the re-built system initramfs img (with kdump capabitiliy)
    # is fully writtent to disk and available for fadump process.
    sync;sync;sync; sleep ${INITRD_BUILD_WAIT_TIME}
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC ConfigFadump

