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


function memblock_mem1g_kaslr()
{
    # oom happened when running on ppc64/ppc64le.
    uname -r | grep ppc64 && return 0
    local free_g=$(free -g | awk '/Mem/ {print $2}')
    #local free_M=$(free -m | awk '/Mem/ {print $2}')
    local use_mem=0x40000000
    local limit=1073741824
    local crashkernel_M=$(awk -F= 'BEGIN{RS=" ";crashreserve=0;b[0]="";} /crashkernel/{gsub("\n",""); split($2,a,","); if (length(a) == 1) a[1]=":"a[1]; for (i in a) {split(a[i],b,":"); ret=gsub("M", "", b[2]); ret=gsub("G", "", b[2]);  if (ret) b[2]=b[2]*1024; crashreserve+=b[2]}} END{print (crashreserve);}' /proc/cmdline) # In MiB
    if ((free_g < 128)); then
        use_mem=$(echo $crashkernel_M + 1024 | bc)
        use_mem=$(echo $use_mem \* 1024 \* 1024 | bc)
        limit=$use_mem
        use_mem=$(echo | awk -v use=$use_mem '{printf("0x%x", use)}')
    fi
    if ((free_g > 128)); then
        use_mem=0x800000000
        limit=34359738368
    fi
    if ((free_g > 500)); then
        use_mem=0x1000000000
        limit=68719476736
    fi
    if ((free_g > 1000)); then
        use_mem=0x1000000000
        limit=68719476736
    fi

    setup_cmdline_args "memblock=debug mem=$use_mem"
    journalctl -k | grep memblock_reserve | grep -o '0x[0-9a-z]*-0x[0-9a-z]*' | sed 's/-/ /g' | while read start end
    do
        mem_start=$(python -c "print($start)")
        mem_end=$(python -c "print($end)")
        rlAssertGreaterOrEqual "Assert no mem beyond limit: "  $limit ${mem_start}
        rlAssertGreaterOrEqual "Assert no mem beyond limit: " $limit ${mem_end}
    done

    cleanup_cmdline_args "memblock mem"
}
