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

function bz817719()
{
    function genstr()
    {
        cat /dev/urandom | tr -dc [:alnum:] | head -c $((RANDOM%20+1))
    }
    function subtest()
    {
        mkdir $1
        for i in `seq 10`; do
            mount -t tmpfs none $1
            dd if=/dev/zero of=$1/$(genstr) bs=1M count=$(($RANDOM%10+1)) 2&>1 >/dev/null
            sleep 0.1
            umount $1
        done
        rm -rf $1
    }
    local mem=$(free -m | grep ^Mem | awk '{print $2}')
    local tasks=$(echo "$mem * 250 / 7000" | bc)
    if [ $tasks -gt 1000 ]; then
        tasks=1000
    fi
    for i in `seq 1 $tasks` ; do
        subtest $(genstr)-$(genstr) &
    done
    wait
    rlLog "Test pass, no kernel PANIC found"
}
