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

    [ $mem_half -gt 1048576 ] && setup_cmdline_args "mem=${mem_half}K" HALF && rlAssertGreaterOrEqual "Assert current memory:$mem_curr" $mem_half $mem_curr
    setup_cmdline_args "mem=${mem_double}K" DOUB

    # there is a possibility that memory total vary from difference reboots.
    if [ $mem_curr -gt $memtotal]; then
	    rlAssertLesserOrEqual "Assert memtotal" $((mem_curr - memtotal)) 1024
    else
	    rlAssertLesserOrEqual "Assert memtotal" $((memtotal - mem_curr)) 1024
    fi

    cleanup_cmdline_args "mem"


}
