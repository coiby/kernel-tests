#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/power-management/rapl/powercap_multirun
#   Description: Check if RAPL powercap works properly.
#   Author: Erik Hamera <ehamera@redhat.com>
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

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        #rlRun "pwd_old=\$(pwd)"
        #rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        #rlRun "pushd $TmpDir"
    rlPhaseEnd

    rlPhaseStartTest
        #debug
        rlRun -l "find /sys/devices/ -name *rapl*"
        rlRun -l "lsmod"

        # Test 1: Check if capping works
        # it should take approx 1.5 - 2 minutes
        rlRun -l "./test_capping.sh"

        rlRun -l "sleep 120"

        # Test 2: Check if capping works 2nd time
        # This test works properly for the second time, but not for the first on some computers.
        # it should take approx 1.5 - 2 minutes
        rlRun -l "./test_capping.sh"

        rlRun -l "sleep 120"

        # Test 3: Check if capping works 3rd time
        # it should take approx 1.5 - 2 minutes
        rlRun -l "./test_capping.sh"

        # process warnings
        rlRun -l "cat ./warn.tmp"
        rlRun -l "./warn.sh"

    rlPhaseEnd

    rlPhaseStartCleanup
        #rlRun "popd"
        #rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
