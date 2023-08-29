#!/bin/bash
# vim: dict=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/hotplug/cpusofthotplug
#   Description: Test for CPU logical online/offline hotplug
#   Author: Jiri Zapletal <jzapleta@redhat.com>
#   Author: William Gomeringer <wgomerin@redhat.com>
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

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

BASE="/sys/devices/system/cpu"
CPUMAX=4096
CONTIME=600

NumActive() {
    cat /proc/schedstat |grep ^cpu |wc -l
}

# @param cpu Cpu number
CpuUp()
{
    local FILE="$BASE/cpu$1/online"
    rlLogInfo "CPU $1 Up"
    [ -f "$FILE" ] || rlAssertExists "$FILE"
    grep -q "^0$" "$FILE" || rlAssertGrep "^0$" "$FILE"
    echo 1 > $FILE
    grep -q "^1$" "$FILE" || rlAssertGrep "^1$" "$FILE"
}

# @param cpu Cpu number
CpuDown()
{
    local FILE="$BASE/cpu$1/online"
    rlLogInfo "CPU $1 Down"
    [ -f "$FILE" ] || rlAssertExists "$FILE"
    grep -q "^1$" "$FILE" || rlAssertGrep "^1$" "$FILE"
    echo 0 > $FILE
    grep -q "^0$" "$FILE" || rlAssertGrep "^0$" "$FILE"
}


RunContinous()
{
    let CNUM=$CNNUM+$CHNUM
    local CPU
    while true
    do
        local N=$(($RANDOM%$CNUM))
        local FILE="$BASE/cpu$N/online"

        [ ! -f "$FILE" ] && continue
        [ $N -eq 0 ] && continue

        if grep -q "^1$" "$FILE"
        then
            rlLogInfo "CPU $N Down"
            echo 0 > "$FILE"
        else
            rlLogInfo "CPU $N Up"
            echo 1 > "$FILE"
        fi
    done
}

# @param cpu Cpu number
HotPluggable()
{
    HP=1    # exit status 0 is success, non-0 is error
    ARCH=$(uname -m)
    if [ -f "$BASE/cpu$1/online" ]
    then
        if [[ "$ARCH" =~ "ppc64" ]]
        then
            # ppc64/ppc64le LPARs expose all physical host CPUs in /sys
            # but only CPUs with a topology subdirectory are hotpluggable
            if [ -d "$BASE/cpu$1/topology" ]
            then
                HP=0
            fi
        elif [ "$ARCH" = "aarch64" ]
        then
            # aarch64 cannot hotplug the primary CPU (yet), so skip it
            # https://bugzilla.redhat.com/show_bug.cgi?id=1243150
            if [ "$1" != "0" ]
            then
                HP=0
            fi
        else
            HP=0
        fi
    fi
    return $HP
}

rlJournalStart
    rlPhaseStartSetup "Setup"
        rlShowRunningKernel

        CORES=""
        CHNUM=0
        CNNUM=0

        rlLog "Checking CPU cores"

        for ((I=0; $I < $CPUMAX; I=$I+1))
        do
            if HotPluggable $I
            then
                    rlLog "CPU $I is hotpluggable"
                    CORES="$CORES $I"
                    let CHNUM=$CHNUM+1
            else
                if [ -d "$BASE/cpu$I" ]
                then
                    rlLog "CPU $I is not hotpluggable"
                    let CNNUM=$CNNUM+1
                fi
            fi
        done
        rlLog "Hotplug Cores: $CORES"
        rlLog "Number of hotpluggable cores: $CHNUM"
        rlLog "Number of non-hotpluggable cores: $CNNUM"
        CTOTAL=$[ $CHNUM + $CNNUM ]
    rlPhaseEnd

    if [ $CTOTAL -eq 1 ]
    then
        rlPhaseStartTest "Skip"
            rlLog "Skip, there is only one core available"
        rlPhaseEnd
        rlJournalPrintText
        rlJournalEnd
    exit 0
    fi

    rlPhaseStartTest "Basic"
        rlLog "Off-line and on-line cores"
        for N in $CORES
        do
            CpuDown $N
            CpuUp $N
        done
    rlPhaseEnd

    rlPhaseStartTest "Continuous"
        rlLog "Running continous test (for $CONTIME sec)"
        RunContinous &
        PID=$!

        sleep $CONTIME

        rlRun "kill $PID; sleep 5" 0 "End of continous test"

        sleep 5 #just wait for sync
    rlPhaseEnd

    rlPhaseStartCleanup
        rlLog "CPU Up for all cores"
        for I in $CORES
        do
            echo 1 > "$BASE/cpu$I/online"
            rlAssertGrep "^1$" "$BASE/cpu$I/online"
        done
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
