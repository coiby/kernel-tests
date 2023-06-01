#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
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

function cgroup_disable_check()
{
    local value;
    value=`echo $(cat /proc/cgroups | sed '/subsys_name/d' | awk '{print $1}') | sed 's/\ /,/g'`

    rlAssertGrep "cgroup_disable=$value" /proc/cmdline
    rlAssert0 "List enabled cgroup controllers" `lssubsys | wc -l`
    mkdir cgroup_disable_mnt
    for subsys in $(cat /proc/cgroups | sed '/subsys_name/d' | awk '{print $1}')
    do
        mount -v -t cgroup -o $subsys cgroup cgroup_disable_mnt | tee ./mount_failed_log
    done
    rlAssertNotGrep "mounted" "./mount_failed_log" && rm -f ./mount_failed_log
}



function cgroup_disable()
{
    local value;
    value=`echo $(cat /proc/cgroups | sed '/subsys_name/d' | awk '{print $1}') | sed 's/\ /,/g'`

    setup_cmdline_args "cgroup_disable=$value"
    cgroup_disable_check
    cleanup_cmdline_args "cgroup_disable"

}

