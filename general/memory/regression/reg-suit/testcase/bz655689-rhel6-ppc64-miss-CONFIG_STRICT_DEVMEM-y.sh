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

function bz655689()
{
    if [ ! -f /proc/rtas/rmo_buffer ]; then
        return
    else
        if rlIsRHEL 8; then
            python=/usr/libexec/platform-python
        else
            python=python
        fi
        rlRun "rmo=`cut -d ' ' -f 1 /proc/rtas/rmo_buffer`"
        rlRun "skip=`$python -c 'print("%ld" % ('0x$rmo' / 0x10000))'`"
        rlRun "dd if=/dev/mem of=/tmp/foo count=1 bs=64k skip=$(($skip-1))" 1 "expected EPERM"
        rlRun "dd if=/dev/mem of=/tmp/foo count=1 bs=64k skip=$skip" 0 "should pass"
        rlRun "dd if=/dev/mem of=/tmp/foo count=1 bs=64k skip=$(($skip+1))" 1 "expected EPERM"
    fi
}
