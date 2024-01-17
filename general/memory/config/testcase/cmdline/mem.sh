#!/bin/bash
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

function align()
{
    local mem=$1
    local alignment=$2
    local mask=$(( alignment - 1 ))
    echo $(( ((mem + mask)&~(mask)) ))
}

function mem()
{
    local mem_curr;
    local memtotal;
    local mem_half;
    local mem_double;

    mem_curr=$(cat /proc/meminfo  | grep MemTotal | awk '{print $2}')
    if [ ! -f ${DIR_DEBUG}/MEMTOTAL ]; then
       echo $mem_curr | tee ${DIR_DEBUG}/MEMTOTAL
    fi
    memtotal=$(cat ${DIR_DEBUG}/MEMTOTAL)
    mem_half=$((memtotal/2))
    mem_double=$((memtotal*2))

    # ppc64 requires 16MB aligned mem= so it can allocate large pages
    # correctly, or it fails to boot [1].  [2] discusses how setting
    # the alignment of the mem= command has been inadvertently dropped
    # from various kernels, which leads to boot hangs.  Align it here
    # to make sure this consistently works.
    #  [1] https://kernel.googlesource.com/pub/scm/linux/kernel/git/tglx/history/+/34f96943a4eb7e3074a91ad847d8ca6ad4a2e97c
    #  [2] https://issues.redhat.com/browse/RHEL-8591
    if uname -r | grep -q ppc64; then
        mem_half=$(align $mem_half 16384)
        mem_double=$(align $mem_double 16384)
    fi

    [ $mem_half -gt 1048576 ] && setup_cmdline_args "mem=${mem_half}K" HALF && rlAssertGreaterOrEqual "Assert current memory:$mem_curr" $mem_half $mem_curr
    setup_cmdline_args "mem=${mem_double}K" DOUB

    # there is a possibility that memory total vary from difference reboots.
    if [ $mem_curr -gt $memtotal ]; then
        rlAssertLesserOrEqual "Assert memtotal" $((mem_curr - memtotal)) 1024
    else
        rlAssertLesserOrEqual "Assert memtotal" $((memtotal - mem_curr)) 1024
    fi

    cleanup_cmdline_args "mem"


}
