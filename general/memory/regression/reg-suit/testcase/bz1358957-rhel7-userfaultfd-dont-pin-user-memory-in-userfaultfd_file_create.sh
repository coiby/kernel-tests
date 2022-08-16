#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   FIXMEHERE
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
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

function bz1358957()
{
    # fixed in kernel-3.10.0-481.el7
    local SZ MAXOF MEMTOTAL
    MEMTOTAL=$(cat /proc/meminfo  | grep MemTotal | awk '{print $2}')
    MAXOF=$(ulimit -n)

    # (total_mem / max_open_files * 2) is the size of each malloc in b
    # that exec half max_open_files times to trigger a OOM, without *2
    # it will use up fds before a OOM.
    SZ=$((MEMTOTAL/MAXOF*2*1024))
    echo "#define SZ $SZ" > SZ.h

    gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c -I.
    if [ $? != 0 ]; then
        rlLog "userfaultfd is not supported"
        return 1
    fi

    rlRun "swapoff -a"
    #expecting running out of fds rather than a OOM
    rlRun "./$FUNCNAME $SZ 2>&1" 127
    rlRun "swapon -a"

}
