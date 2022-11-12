#!/bin/bash
# vim: dict=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/hotplug/memsofthotplug
#   Description: Test for memory online/offline hotplug
#   Author: William Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc. All rights reserved.
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

# Include rhts environment. Comment out for now while testing script
. /usr/bin/rhts-environment.sh
. /usr/share/rhts-library/rhtslib.sh

PACKAGE="kernel"
BASE="/sys/devices/system/memory"
# Not sure what this should be right now. The way memory hotplug works
# is that the entire available memory is broken into chunks, or sections.
# The size of a section is architecture dependent. In the case of x86_64
# it is broken into 8000000 byte sections. This setting is available in
# /sys/devices/system/memory/block_size_bytes. On a system with 64GB of
# RAM this breaks down to 0-527 sections, or 528 sections. Unlike CPU
# hotplugging at the moment, memory0 is hot pluggable. I suppose we could
# do the math and figure out the limit to the number of sections if the
# theoretical limit for ram under x86_64 in RHEL 6 is 64TB. For now we'll
# just use 528 sections max, until we run across a system with more RAM.
MEMMAX=528
#CONTIME=600
CONTIME=20

MemUp()
{
        local FILE="$BASE/memory$1/state"

        if
        grep "offline" "$FILE"; then
                rlLog "Attempting to online memory block $1"
                echo online > $FILE
                rlLog "Memory block $1 is back online"
        fi
        rlLog "================================================================================================="
}

MemDown()
{
        local FILE="$BASE/memory$1/state"

        if
        grep "online" "$FILE"; then
                rlLog "Attempting to offline memory block $1"
                echo offline > $FILE
        else
                rlLog "Memory block $1 already offline"
        fi

        if
        rlAssertGrep "offline" "$FILE"; then
                rlLog "Memory block $1 successfully offlined"
        else
                rlLog "ERROR: Could not offline memory block $1"
        fi
}

rlJournalStart
    rlPhaseStartSetup "Checking current state of each hot removable memory block"
        rlAssertRpm $PACKAGE
        rlShowRunningKernel

        BLOCKS=""
        CHNUM=0
        CNNUM=0

        rlLog "Checking Memory blocks"

        for ((i = 0; i < $MEMMAX; i++))
        do
                if [ -f "$BASE/memory$i/state" ]
                then
                                MEMSTATE=`cat $BASE/memory$i/state`
                                rlLog "Memory block $i is hotpluggable and is currently $MEMSTATE"
                                BLOCKS="$BLOCKS $i"
                                let CHNUM=$CHNUM+1
                else
                        if [ -d "$BASE/memory$i" ]
                        then
                                rlLog "Memory block $i is not hotpluggable"
                                let CNNUM=$CNNUM+1
                        fi
                fi
        done
        rlLog "Hotplug blocks: $BLOCKS"
        rlLog "Number of hotpluggable blocks: $CHNUM"
        rlLog "Number of non-hotpluggable blocks: $CNNUM"
     rlPhaseEnd

    rlPhaseStartTest "Basic test: Off-line and on-line all memory sections in order"
        rlLog "Begin Basic test"
        for N in $BLOCKS
        do
                MemDown $N
                MemUp $N
        done
    rlPhaseEnd

    rlPhaseStartCleanup
       rlLog "Bring all memory blocks back online"
        for i in $BLOCKS
        do
                echo "online" > "$BASE/memory$i/state"
                rlAssertGrep "online" "$BASE/memory$i/state"
        done
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd

