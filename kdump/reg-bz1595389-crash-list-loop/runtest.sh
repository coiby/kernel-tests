#!/bin/sh

# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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

#  Author: Xiaowu Wu    <xiawu@redhat.com>
#  Update: Ruowen Qin   <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1595389 - RFE: add alternative loop detection to list command that
#               avoids large memory usage for large lists
# Fixed in RHEL-7.7 crash-7.2.3-9.el7
CheckSkipTest crash 7.2.3-9 && Report

ConfigCrash() {
    PrepareCrash
}

CrashVmcoreCheck() {

    # Check if a vmcore has been saved
    GetCorePath

    # run crash command list and list -B tests
    CheckVmlinux

    cat <<EOF >"crash_list.cmd"
list vmap_area.list -H vmap_area_list
exit
EOF

    cat <<EOF >"crash_list_rev.cmd"
list -r vmap_area.list -H vmap_area_list
exit
EOF

    cat <<EOF >"crash_list_brent.cmd"
list -B vmap_area.list -H vmap_area_list
exit
EOF

    cat <<EOF >"crash_list_brent_rev.cmd"
list -B -r vmap_area.list -H vmap_area_list
exit
EOF

    RhtsSubmit "crash_list.cmd"
    RhtsSubmit "crash_list_rev.cmd"
    RhtsSubmit "crash_list_brent.cmd"
    RhtsSubmit "crash_list_brent_rev.cmd"

    Log "Efficiency of list commands w/ and w/o -B option is expected to be seen in memory usage, not in execution time."
    for i in "crash_list.cmd" "crash_list_rev.cmd" "crash_list_brent.cmd" "crash_list_brent_rev.cmd"; do
        Log "Run crash command $i"
        # shellcheck disable=SC2154
        time crash -i "$i" "${vmlinux}" "${vmcore}" > "$i".out
        ret=$?
        RhtsSubmit "$(pwd)/$i.out"
        [ "$ret" -ne 0 ] && Error "Crash command returns error code ${ret}"
    done

    # Output of list crash with/without B should be same
    Log "Compare crash list output with/without B(brent) - exclude the crash command itself"
    sed -i '/crash> list /d' crash_list.cmd.out
    sed -i '/crash> list /d' crash_list_brent.cmd.out
    LogRun "diff crash_list.cmd.out crash_list_brent.cmd.out"
    [ "$?" -ne 0 ] && Error "crash cmd 'list' returns different outputs w/ and w/o -B"

    sed -i '/crash> list /d' crash_list_rev.cmd.out
    sed -i '/crash> list /d' crash_list_brent_rev.cmd.out
    LogRun "diff crash_list_rev.cmd.out crash_list_brent_rev.cmd.out"
    [ "$?" -ne 0 ] && Error "crash cmd 'list -r' returns different outputs w/ and w/o -B"
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC ConfigCrash CrashVmcoreCheck
