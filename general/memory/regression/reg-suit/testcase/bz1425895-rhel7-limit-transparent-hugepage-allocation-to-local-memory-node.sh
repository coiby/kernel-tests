#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
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

function bz1425895()
{
    which numactl || return

    local loops=${LOOPS:-1}

    local node1_size=$(numactl -H | grep 'node 1 size:' | awk '{print $4}')
    local pid=""
    local numamaps=""
    local node=1
    rlRun -l "swapon -s" 0 "show swap info"
    if [ -z "$node1_size" ]; then
        rlLog "Skip: This case requires at least 2 nodes."
        rlRun "numactl -H"
        uname -m | grep -qE "x86_64|ppc64le|aarch64" || return
        rlLog "Tring to use node0 as a try-my-best test"
        local node1_size=$(numactl -H | grep 'node 0 size:' | awk '{print $4}')
        node=0
    fi
    if [ -e /sys/kernel/mm/transparent_hugepage/enabled ]; then
        rlRun "echo always > /sys/kernel/mm/transparent_hugepage/enabled"
    fi
    rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"
    numactl --membind=$node ./$FUNCNAME $node1_size $loops &
    pid=$!
    sleep 1

    while ps -p "$pid" | grep -q "$pid"; do
        numamaps=$(cat /proc/$pid/numa_maps | grep "anon=[0-9][0-9][0-9]")
        rlRun "echo $numamaps | grep "N[^$node]="" 1-255
        sleep 5
    done
}
