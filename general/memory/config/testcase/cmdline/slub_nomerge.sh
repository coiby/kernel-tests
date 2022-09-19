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

function slub_nomerge_check()
{
    pushd $DIR_SOURCE/slabtest
    rlRun "make"
    rlRun "insmod slabtest.ko"
    # without slub_nomerge parameter, slabtest-32 will be merged
    # into kmalloc-32 for rhel7, did not supported for rhel6.
    rlAssertGrep "slabtest-32" /proc/slabinfo
    rlRun "rmmod slabtest"
    popd
}



function slub_nomerge()
{
    grep slub_nomerge /proc/kallsyms
    if [ $? != 0 ]; then
        rlLog "slub_nomerge is not supported."
        return 0
    fi

    setup_cmdline_args "slub_nomerge" && slub_nomerge_check
    cleanup_cmdline_args "slub_nomerge"
}

