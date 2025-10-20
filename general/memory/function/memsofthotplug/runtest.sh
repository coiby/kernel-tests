#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/hotplug/memsofthotplug
#   Description: Test for memory online/offline hotplug
#   Author: William Gomeringer <wgomerin@redhat.com>
#   Re-write: Li Wang <liwang@redhat.com>
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

# Include rhts environment. Comment out for now while testing script
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE=$(rpm --queryformat '%{name}\n' -qf /boot/config-$(uname -r) | sed -e s/-core//)
NODES=`numactl -H | grep available | cut -d ' ' -f 2`
BASE="/sys/devices/system/node/node$(($NODES-1))"

NodesCheck()
{
        if [ $NODES -lt 2 ]; then
            rlLog "The NUMA NODES should be more than 2"
            rstrnt-report-result Test_Skipped PASS 99
            rlPhaseEnd
            rlJournalPrintText
            rlJournalEnd
            exit 0
        fi
}


MemUp()
{
        local FILE="$1/state"

        if
        grep "offline" "$FILE"; then
                rlLog "Attempting to online memory block $1"
                echo online > $FILE
                rlLog "Memory block $1 is back online"
        fi
        rlLog "========================================================================="
}

MemDown()
{
        local FILE="$1/state"

        if grep "online" "$FILE"; then
                rlLog "Attempting to offline memory block $1"
                echo offline > $FILE
        else
                rlLog "Memory block $1 already offline"
        fi

        if grep "offline" "$FILE"; then
                rlLog "Memory block $1 successfully offlined"
        else
                rlLog "ERROR: Could not offline memory block $1"
        fi
}

rlJournalStart
    rlPhaseStartSetup "Checking current state of each removable memory block"
        rlAssertRpm $PACKAGE
        rlShowRunningKernel

        NodesCheck
        BLOCKS=""
        CHNUM=0
        CNNUM=0

        rlLog "Checking Memory blocks"

        for i in ${BASE}/memory*; do
            REMOVABLE=`cat ${i}/removable`
                if [ $REMOVABLE -eq 1 ]
                then
                                rlLog "Memory block $i is removable"
                                BLOCKS="$BLOCKS $i"
                                let CHNUM=$CHNUM+1
                else
                        if [ -d "$i" ]
                        then
                                rlLog "Memory block $i is not removable"
                                let CNNUM=$CNNUM+1
                        fi
                fi
        done
        rlLog "Hotplug blocks: $BLOCKS"
        rlLog "Number of removable blocks: $CHNUM"
        rlLog "Number of non-removable blocks: $CNNUM"
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
                echo 1 > "$i/online"
                rlAssertGrep "online" "$i/state"
        done
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd

