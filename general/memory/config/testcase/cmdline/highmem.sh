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

function highmem()
{
    local mem_curr;
    local memtotal;
    local mem_half;
    local mem_double;

    mem_curr=$(cat /proc/meminfo  | grep HighTotal | awk '{print $2}')
    if [ -z "$mem_curr" ]; then
        rlRun "echo Did not find highmem."
        return 0
    fi
    if [ ! -f ${DIR_DEBUG}/MEMTOTAL ]; then
       echo $mem_curr | tee ${DIR_DEBUG}/MEMTOTAL
    fi
    memtotal=$(cat ${DIR_DEBUG}/MEMTOTAL)
    mem_half=$((memtotal/2))
    mem_double=$((memtotal*2))

    setup_cmdline_args "highmem=${mem_half}K" HALF && rlAssertGreaterOrEqual "Assert current highmem:$mem_curr" $mem_half $mem_curr
    setup_cmdline_args "highmem=${mem_double}K" DOUB && rlAssertEquals "Assert total highmem" $memtotal $mem_curr
    setup_cmdline_args "highmem=0" ZERO && rlAssertEquals "Assert zero highmem" "0" $mem_curr

    cleanup_cmdline_args "highmem"


}
