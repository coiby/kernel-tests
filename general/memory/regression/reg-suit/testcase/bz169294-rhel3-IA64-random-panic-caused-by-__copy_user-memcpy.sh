#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 169294
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

function bz169294()
{
    if [ "$(rlGetPrimaryArch)" != "ia64" ]; then
        rlLogWarning "Only for IA64"
        return
    fi
    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogWarning "Can't build test binary"
        return
    fi
    local start=A000000000000000
    local end=A000000001000000
    local pgsize=4000
    local ulimit_size=2049
    local num=0

    rlRun "ulimit -n $ulimit_size"
    while [ $num -lt 15 ]; do
        num=`expr $num + 1`
        uaddr=$start
        while [ "$uaddr" != "$end" ]; do
            laddr=`echo $uaddr | tr \[:upper:\] \[:lower:\]`
            ./$FUNCNAME "0x$laddr"
            uaddr=`echo "obase=16; ibase=16; $uaddr + $pgsize" | bc`
        done
    done
    rlLog "System didn't crash"
}
