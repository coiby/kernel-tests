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


function memblock_mem_kaslr()
{
    local mem_half;

    if [ ! -f $DIR_DEBUG/${FUNCNAME}_memhalf ]; then
        mem_half=$(cat /proc/meminfo  | grep MemTotal | awk '{print $2}')
        mem_half=$((mem_half / 2))
    else
        mem_half=$(cat $DIR_DEBUG/${FUNCNAME}_memhalf)
    fi

    rlLogWarning "This is bogus, need to take care of crashkernel on s390x, aarch64, and ppc64"

    if ! uname -m | grep x86_64; then
        return
    fi

    if [ "$mem_half" -lt "524288" ]; then
        rlRun "echo memory is too low, $((mem_half*2))K"
        return 0
    fi
    rlRun "echo $mem_half > $DIR_DEBUG/${FUNCNAME}_memhalf"

    setup_cmdline_args "memblock=debug mem=${mem_half}K"
    mem_half=$((mem_half*1024))
    grep memblock_reserve /var/log/dmesg | grep -o '0x[0-9a-z]*-0x[0-9a-z]*' | sed 's/-/ /g' | while read start end
    do
        mem_start=$(python -c "print $start")
        mem_end=$(python -c "print $end")
        rlAssertGreaterOrEqual "Assert no mem beyond limit: " ${mem_half} ${mem_start}
        rlAssertGreaterOrEqual "Assert no mem beyond limit: " ${mem_half} ${mem_end}
    done

    cleanup_cmdline_args "memblock mem"
    rm -f $DIR_DEBUG/${FUNCNAME}_memhalf
}
