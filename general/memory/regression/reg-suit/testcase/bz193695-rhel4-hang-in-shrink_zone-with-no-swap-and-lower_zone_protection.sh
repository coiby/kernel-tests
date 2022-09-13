#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Bug 193695 - Hang in shrink_zone with no swap and lower_zone_protection > 0
#   Author: Chao Ye <cye@redhat.com>
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

function bz193695()
{
    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogWarning "Can't build test binary"
        return
    fi
    if ! [ -f /proc/sys/vm/lowmem_reserve_ratio ]; then
        rlLogWarning "/proc/sys/vm/lowmem_reserve_ratio now found"
        return
    fi
    rlRun "cat /proc/sys/vm/lowmem_reserve_ratio"
    rlRun "cat /proc/sys/vm/lowmem_reserve_ratio > bz193695.ratio"
    rlRun "echo '100 100 0' > /proc/sys/vm/lowmem_reserve_ratio"
    ./$FUNCNAME 1024 &
    ./$FUNCNAME 1024 &
    wait %1
    wait %2
    rlRun "cat bz193695.ratio > /proc/sys/vm/lowmem_reserve_ratio"
}
