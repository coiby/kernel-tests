#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   FIXMEHERE
#   Description: 
#   Author: Chao Ye <cye@redhat.com>
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

function bz773522()
{
    if rlIsRHEL ">=7.0" || rlIsFedora ">=23"; then
        local dir=/sys/fs/cgroup
    elif rlIsRHEL 6; then
        local dir=/cgroup
    fi

    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogWarning "Can't build test binary"
        return
    fi

    rlRun "cgroup_display / memory" 0-254
    rlRun "cgroup_create bz773522_1 memory"
    rlRun "cgroup_create bz773522_2 memory"

    if [ "$CGROUP_VERSION" = 1 ]; then
        rlRun "echo 1 > $(cgroup_get_path bz773522_1 memory)/notify_on_release"
        rlRun "echo 1 > $(cgroup_get_path bz773522_2 memory)/notify_on_release"
        rlRun "cgroup_set_file bz773522_1 memory memory.move_charge_at_immigrate=3"
        rlRun "cgroup_set_file bz773522_2 memory memory.move_charge_at_immigrate=3"
    fi

    cgexec.sh bz773522_1 memory ./$FUNCNAME &

    # Attention. If the cgexec executing in backgroupd is not done when first cgclassify, it will cause 
    # the first cgclassify failure.So wait for the above cgexec for 5 seconds.It's proved work.
    sleep 5;

    for i in `seq 30`; do
        rlRun "cgroup_set_file bz773522_2 memory tasks=`pidof $FUNCNAME`"
        rlAssertGrep bz773522_2 /proc/`pidof $FUNCNAME`/cgroup
        sleep 1
        rlRun "cgroup_set_file bz773522_1 memory tasks=`pidof $FUNCNAME`"
        rlAssertGrep bz773522_1 /proc/`pidof $FUNCNAME`/cgroup
        sleep 1
    done

    rlRun "pkill $FUNCNAME"
    sleep 2
    cgroup_destroy bz773522_1 memory
    cgroup_destroy bz773522_2 memory
}
