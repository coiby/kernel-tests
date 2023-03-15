#!/bin/bash
# vim: dict=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/power-management/tmon
#   Description: Check for the presence of thermal monitoring
#   Author: Erik Hamera <ehamera@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc. All rights reserved.
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

PACKAGE="kernel-tools"
BASE="/sys/devices/virtual"

rlJournalStart
    rlPhaseStartSetup "Checking for the existance of kernel-tools, which contains the tmon package"
        # Currently the absence of kernel-tools shouldn't be considered a failure as we are not (yet) relying
        # on tmon for any functionality
        rlAssertRpm $PACKAGE
        rlShowRunningKernel
    rlPhaseEnd

    rlPhaseStartTest "Starting Test"
        rlLog "Does the box support thermal monitoring?"
        if [ -d "$BASE/thermal" ]
        then
            rlLog "Thermal devices/zones found"
                for i in $(ls -d $BASE/thermal/*); do
                echo ${i%%/} | awk -F/ '{print $NF}'
            done
        else
            rlWarn "No thermal devices/zones available"
        fi
    rlPhaseEnd "End Test"

rlJournalPrintText
rlJournalEnd
