#!/bin/bash
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

function slub_min_order_check()
{
    local slabinfo
    slabinfo=$(cat /proc/slabinfo | sed  '1,2d' | awk '{if ($6 < 2) print $6 }')
    if [ -z "$slabinfo" ]; then
        rlPass "All slabs at least have 2 pages, slub_min_order=1"
    else
        echo $slabinfo
        rlFail "Shouldn't have slabs less then 2 pages, slub_min_order=1"
    fi
}



function slub_min_order()
{
    grep slub_min_order /proc/kallsyms
    if [ $? != 0 ]; then
        rlLog "slub_min_order is not supported."
        return 0
    fi

    setup_cmdline_args "slub_min_order=1" && slub_min_order_check
    cleanup_cmdline_args "slub_min_order"
}

