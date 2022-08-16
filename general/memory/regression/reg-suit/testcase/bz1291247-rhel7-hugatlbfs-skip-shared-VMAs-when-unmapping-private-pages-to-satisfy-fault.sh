#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
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

function bz1291247()
{
    if ! grep -q hugetlbfs /proc/filesystems; then
        rlLog "hugetlbfs is not supported"
        return
    fi

    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogWarning "Can't build test binary"
        return
    fi

    rlRun "mkdir huge_test"
    rlRun "mount -t hugetlbfs hugetlbfs huge_test"

    # Alloc two hugepages, and reproducer will map 1 page privatly,
    # 1 page shared, then fork a child, and do COW.
    # When bz reproduced, the process will stall in D state. BUG_ON
    # trace can be found in dmesg.
    rlRun "sysctl -w vm.nr_hugepages=2"
    local NRHUGEPAGES=$(cat /proc/sys/vm/nr_hugepages)
    if [ "$NRHUGEPAGES" != "2" ]; then
        rlLogWarning "Cannot alloc 2 hugepages for testing, probabily becasue it's low memory system."
        return
    fi
    rlRun "./$FUNCNAME"

    rlRun "sysctl -w vm.nr_hugepages=0"
    rlRun "umount huge_test"

}
