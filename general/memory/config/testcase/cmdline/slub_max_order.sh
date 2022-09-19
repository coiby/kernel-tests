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

function slub_max_order_check()
{
    local slabinfo
    slabinfo=$(cat /proc/slabinfo | sed  '1,2d' | awk '{if ($6 == 16) print  }')
    if [ ! -z "$slabinfo" ]; then
        rlPass "There should be slabs have 16 pages, slub_max_order=4"
    else
        echo $slabinfo
        rlPass "There were not slabs have 16 pages, slub_max_order=4"
    fi
}



function slub_max_order()
{
    grep slub_max_order /proc/kallsyms
    if [ $? != 0 ]; then
        rlLog "slub_max_order is not supported."
        return 0
    fi

    setup_cmdline_args "slub_max_order=4" && slub_max_order_check
    cleanup_cmdline_args "slub_max_order"
}

