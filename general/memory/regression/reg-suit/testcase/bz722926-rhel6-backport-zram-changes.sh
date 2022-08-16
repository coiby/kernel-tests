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

function bz722926()
{
    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogWarning "Can't build test binary"
        return
    fi
    
    if ! lsmod | grep -q zram; then
        if ! rlRun "modprobe zram" 0-255; then
	    rlLogWarning "kmod zram is not supported."
            return 1
        fi
        rlRun "echo $((50 * 1024 * 1024)) > /sys/block/zram0/disksize"
    fi

    for i in `seq 100`; do
        # Concurrent un-/compressed write accesses:
        # fill a 1000 times the first block of zram0 with '*' (compressible)
        ./$FUNCNAME -wb 4096 -l 1000 /dev/zram0 0 &
        # fill a 1000 times the first block of zram0 with random bytes (uncompressible)
        ./$FUNCNAME -wb 4096 -l 1000 -r /dev/zram0 0
        sleep 1
        # Concurrent r/w accesses:
        # write a 1000 times the first block of zram0
        ./$FUNCNAME -wb 4096 -l 1000 /dev/zram0 0
        # read a 1000 times the first block of zram0
        ./$FUNCNAME -b 4096 -l 1000 /dev/zram0 0
        sleep 1
    done
}
