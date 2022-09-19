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

function slub_min_objects_check()
{
    local num_objects
    pushd $DIR_SOURCE/slabtest
    rlRun "make"
    rlRun "insmod slabtest.ko"
    num_objects=$(grep "slabtest-32" /proc/slabinfo | awk '{print $3}')
    rlAssertGreaterOrEqual "Assert num_objects for slabtest-32 greater than 300." $num_objects 300
    rlRun "rmmod slabtest"
    popd
}



function slub_min_objects()
{
    grep slub_min_objects /proc/kallsyms
    if [ $? != 0 ]; then
        rlLog "slub_min_objects is not supported."
        return 0
    fi

    setup_cmdline_args "slub_nomerge slub_min_objects=300" && slub_min_objects_check
    cleanup_cmdline_args "slub_nomerge slub_min_objects"
}

