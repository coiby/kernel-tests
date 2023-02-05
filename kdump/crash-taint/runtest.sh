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

# Bug 1845358 - Backport panic_on_taint kernel functionality
# https://bugzilla.redhat.com/show_bug.cgi?id=1845358
# panic_on_taint is enabled since kernel-4.18.0-216.el8 (RHEL-8.3)

# Bug 1845356 - Backport panic_on_taint kernel functionality
# https://bugzilla.redhat.com/show_bug.cgi?id=1845356
# panic_on_taint is enabled since kernel-3.10.0-1151.el7 (RHEL-7.9)

ConfigTaint() {
    Log "Check if panic_on_taint is enabled"
    LogRun "journalctl | grep \"panic_on_taint:\" | grep \"bitmask=0x440\""
    if [ $? -ne 0 ]; then
        cat /proc/cmdline
        MajorError "panic_on_taint is not enabled."
        return
    fi
}

TriggerTaintPanic(){
    Log "Triger taint panic"
    sync;sync;sync; sleep 10
    echo 64 > /proc/sys/kernel/tainted
}

# --- start ---

Multihost SystemCrashTest TriggerTaintPanic ConfigTaint

