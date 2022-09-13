#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1405920 - divide by zero exception: /proc/sys/vm/percpu_pagelist_fraction
#   Description: 
#   Author: Chao Ye <cye@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc. All rights reserved.
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

function one_round()
{
    echo always > /sys/kernel/mm/transparent_hugepage/enabled
    ./bz1409913 &
    sleep 1
    rss1=$(pmap -x $! | tail -1 | awk '{print $4}')
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    ./bz1409913 &
    sleep 1
    rss2=$(pmap -x $! | tail -1 | awk '{print $4}')

    rssdiff=$((rss1-rss2))
    pkill bz1409913
    (( ${rssdiff#-} <= 200 ))
}

function bz1409913()
{
    #local rss1 rcc2 thpcfg rssdiff
    yum install -y procps-ng
    rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"
    thpcfg=$(cat /sys/kernel/mm/transparent_hugepage/enabled  | grep -o '\[.*\]' | grep -o '[a-z]*')

    local loop
    for ((loop=0; loop<3; loop++)); do
        echo "loop=$loop"
        one_round && break
    done

    # clean up
    echo $thpcfg > /sys/kernel/mm/transparent_hugepage/enabled
    rlAssertLesserOrEqual "rss1=$rss1 rss2=$rss2 diff=$rssdiff, diff should less than 200" ${rssdiff#-} 200
}
