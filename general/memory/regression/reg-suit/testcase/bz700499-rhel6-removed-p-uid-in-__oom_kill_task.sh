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

function bz700499()
{
    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogWarning "Can't build test binary"
        return
    fi
    yum install -y libcgroup-tools libcgroup strace samba numactl
    rlServiceStart cgconfig
    cgroup_create test memory

    cgroup_set_file test memory memory.limit_in_bytes=10M
    rlAssertEquals "Check memory.limit_in_bytes value" $(cgroup_get_file test memory memory.limit_in_bytes) 10485760

    if [ "$CGROUP_VERSION" = 1 ]; then
        cgroup_set_file test memory memory.memsw.limit_in_bytes=10M
        rlAssertEquals "Check memory.memsw.limit_in_bytes value" $(cgroup_get_file test memory memory.memsw.limit_in_bytes) 10485760
    else
        cgroup_set_file test memory memory.memsw.limit_in_bytes=0
        rlAssertEquals "Check memory.memsw.limit_in_bytes value" $(cgroup_get_file test memory memory.memsw.limit_in_bytes) 0
    fi
    dmesg -c > /dev/null
    cgexec.sh test memory ./$FUNCNAME &
    sleep 1
    local pid=`pidof $FUNCNAME`
    wait
    dmesg > $FUNCNAME.log
    rlAssertGrep $pid $FUNCNAME.log
    rlRun "cgroup_destroy test memory"
}
