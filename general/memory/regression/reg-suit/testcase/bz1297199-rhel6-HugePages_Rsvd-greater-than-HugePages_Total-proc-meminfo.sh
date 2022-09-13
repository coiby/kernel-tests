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

function bz1297199()
{
    if [ "$(rlGetPrimaryArch)" != "x86_64" ]; then
        rlLog "Only for x86_64"
        return
    fi

    if ! grep -q hugetlbfs /proc/filesystems; then
        rlLog "hugetlbfs is not supported"
        return
    fi

    if rlIsRHEL ">=9"; then
        report_result "${FUNCNAME}_lds_broken" SKIP
        return
    fi

    rlRun "g++ -c -o ${FUNCNAME}_main.o ${DIR_SOURCE}/${FUNCNAME}_main.cpp"
    rlRun "g++ -c -o ${FUNCNAME}_shm.o ${DIR_SOURCE}/${FUNCNAME}_shm.cpp"
    rlRun "g++ -Wl,-T,${DIR_SOURCE}/${FUNCNAME}_test.lds -ldl -o ${FUNCNAME}_shm ${FUNCNAME}_main.o ${FUNCNAME}_shm.o"
    if [ $? != "0" ]; then
        rlLogWarning "Can't build test binary"
        return
    fi
    rlRun "sysctl -w vm.nr_hugepages=10"
    local HUGEPAGE_RSVD=$(grep HugePages_Rsvd /proc/meminfo  | awk '{print $2}')
    rlAssert0 "HugePages_Rsvd should be 0" $HUGEPAGE_RSVD

    rlRun "HUGEPAGE_TEXT=1 gdb  ./${FUNCNAME}_shm -ex 'b main' -ex run -ex continue -ex quit"
    HUGEPAGE_RSVD=$(grep HugePages_Rsvd /proc/meminfo  | awk '{print $2}')
    rlAssert0 "HugePages_Rsvd should be 0" $HUGEPAGE_RSVD

    rlRun "sysctl -w vm.nr_hugepages=0"
}
