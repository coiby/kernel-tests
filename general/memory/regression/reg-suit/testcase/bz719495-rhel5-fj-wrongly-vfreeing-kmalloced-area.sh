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

function bz719495()
{
    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogWarning "Can't build test binary"
        return
    fi
    local nr_max=$(cat /proc/sys/fs/file-max)
    local old_nr_file=$(ulimit -n)
    local low_size=$(free -lk | grep -i Low | awk '{print $4}')
    if [ -n "$low_size" ];then
        let "low_size = ($low_size / 3) * 2"
        [ $low_size -gt 500000 ] && low_size=500000
    else
        low_size=200000
    fi
    local nr_file=$((nr_max-1000))
    if [ $nr_file -gt $low_size ]; then
        nr_file=$low_size
    fi
    rlRun "ulimit -n $nr_file"
    dmesg -c > /dev/null
    rlRun "./$FUNCNAME $nr_file"
    rlRun "ulimit -n $old_nr_file"
    echo "" >/var/log/audit/audit.log
    if dmesg | grep -q "Trying to vfree() nonexistent vm area"; then
        rlFail "Test failed: vfree()ed nonexistent vm area"
    fi
}
