#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   FIXMEHERE
#   Author: Wang Shu <shuwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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

function bz1109489()
{
    local fixcode='avg_atom = p->se.sum_exec_runtime'
    local srcpkg="kernel-debuginfo-common-$(uname -m)"
    yum install -y systemtap kernel-debuginfo kernel-devel
    rpm -q $srcpkg
    if [ $? != 0 ]; then
        rlLogWarning "Skipped, no $srcpkg found"
        mark_skip "bz1109489" "no $srcpkg found"
        return 0
    fi

    local srcfile_path=$(rpm -ql $srcpkg | grep kernel.sched.debug.c)
    local srcfile_name=$(rpm -ql $srcpkg | grep -o kernel.sched.debug.c)
    local srcline=$(grep -n "$fixcode" $srcfile_path | awk -F ':' '{print $1}')

    rlLog "src: $srcfile_name, lineno: $srcline"
    rlLog "Running systemtap to trigger crash"

    echo 1 > /proc/sys/kernel/sched_schedstats
    stap  -g -ve  "probe kernel.statement(\"*@${srcfile_name}:${srcline}\") \
        { \$nr_switches = 0x100000000; exit()}" \
        -c 'cat /proc/self/sched' > schedlog 2>&1
    rlRun "cat schedlog"
    echo 0 > /proc/sys/kernel/sched_schedstats

    return 0;

}
