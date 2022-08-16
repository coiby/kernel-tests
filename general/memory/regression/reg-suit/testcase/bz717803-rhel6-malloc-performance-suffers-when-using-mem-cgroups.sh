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

function bz717803()
{
    if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c -lrt"; then
        rlLogWarning "Can't build test binary"
        return
    fi
    function calctime()
    {
        local runtime=0
        for cost in $(cat $1); do
            runtime=$(echo "$runtime + $cost" | bc)
        done
        echo $runtime
    }
    # Test without cgroups
    for i in `seq $CPUCOUNT`; do
        (./$FUNCNAME -s 1024 -n 1000 &) | tee -a ${FUNCNAME}.log
    done
    # Test with cgoups
    rlRun "cgroup_create $FUNCNAME memory"
    for i in `seq $CPUCOUNT`; do
        (cgexec.sh $FUNCNAME memory ./$FUNCNAME -s 1024 -n 1000 &) | tee -a ${FUNCNAME}-cgroup.log
    done
    local time1=$(calctime ${FUNCNAME}.log)
    local time2=$(calctime ${FUNCNAME}-cgroup.log)

    rlAssert0 "Check Inside/Outside cgroups runtime" $(echo "${time2} > ${time1} * 2" | bc)
    rlRun "cgroup_destroy $FUNCNAME memory"
}
