#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Chunyu Hu <chuhu@redhat.com>
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


function use_after_free()
{
    local num_objects
    pushd $DIR_SOURCE/debug_pagealloc
    rlRun "make"
    rlRun "insmod debug_pa.ko"
    rlRun "rmmod debug_pa"
    popd
    rlRun "dmesg | grep 'BUG: unable to handle kernel' || grep ' BUG: unable to handle kernel' /var/log/messages"
    this_retval=$?
}

function debug_pagealloc()
{
    [ ! "$NEGATIVE" = 1 ] && return
    local debug_kernel
    local support=$(grep _debug_guardpage_minorder /proc/kallsyms)
    [ -z "$support" ] && rlLog "debug_guardpage_minorder is not supported." && return 0
    setup_cmdline_args "debug_pagealloc=on debug_guardpage_minorder=2" DEBUG_PAGEALLOC && use_after_free
    cleanup_cmdline_args "debug_pagealloc=on debug_guardpage_minorder=2"
    [ -n "$this_retval" ] && return $this_retval
    return 0
}

