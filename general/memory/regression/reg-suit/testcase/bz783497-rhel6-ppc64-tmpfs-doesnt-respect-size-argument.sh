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

function bz783497()
{
    local freemem=$(free -m | grep ^Mem | awk '{print $4}')
    if [ $freemem -lt 130 ]; then
        rlLogWarning "System free memory less than 130, test skipped"
        return
    fi
    local mp=/$FUNCNAME
    rlRun "mkdir -p $mp"
    rlRun "mount -t tmpfs -o size=128m tmpfs /$FUNCNAME"
    rlRun "stat -f $mp"
    local bs=$(stat -c %s -f /$FUNCNAME)
    local nr=$(stat -c %a -f /$FUNCNAME)
    rlRun "dd if=/dev/zero of=/$FUNCNAME/first bs=$bs count=$nr"
    rlAssertEquals "Available should be 0" $(stat -c %a -f /$FUNCNAME) 0
    rlRun "stat -f /$FUNCNAME"
    rlRun "dd if=/dev/zero of=/$FUNCNAME/second bs=$bs count=1" 1
    rlAssertEquals "Available should be 0" $(stat -c %a -f /$FUNCNAME) 0
    rlRun "umount /$FUNCNAME"
    rlRun "rm -rf /$FUNCNAME"
}
