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

function hugepagesz()
{
    local nr_1g_huges
    local total_mem
    rlRun "cat /proc/meminfo  | grep '^Huge\|Mem'"
    grep -q pdpe1gb /proc/cpuinfo
    if [ $? != 0 ]; then
        rlRun "echo 1G hugepage is not supported"
        return 0
    fi
    total_mem=`cat /proc/meminfo  | grep MemTotal | awk '{print $2}'`
    if [ $total_mem -lt 8388608 ]; then
        rlLog "MemTotal=${total_mem}K, needs 8G to test 1G hugepage."
        return 0
    fi
    setup_cmdline_args "hugepagesz=1G hugepages=2"
    nr_1g_huges=`echo $(cat /sys/devices/system/node/node*/hugepages/hugepages-1048576kB/nr_hugepages) | sed 's/\ /+/g' | bc`
    rlAssertGreaterOrEqual "Assert at least one 1G hugepage" $nr_1g_huges 1
    cleanup_cmdline_args "hugepagesz hugepages"
}
