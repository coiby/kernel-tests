#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/power-management/rapl/powerclamp_in_steps_by_5
#   Description: Test powerclamp in different settings
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
        # Test 1: Create output - this part can get more than 30 minutes
        # The shorter the runtime for each test, the higher the probability
        # of incorrect numbers. There is no atomic reading in RAPL.
        rlRun -l "./00_gather_clamp_data__by5.sh 600"

        # for debug
        rlRun -l "ls"

        # Test 2: Is reported power consumption bigger for bigger load?
        # prepares file power.tmp for test 3
        rlRun -l "./01_compare_loads.sh"

        # Test 3: Is power consumption during clamped (to 51%) full load
        # approx. average between idle and unclamped full load?
        rlRun -l "./03_check_clamped.py"


        #Check if there was a warning during testing
        rlRun -l "cat ./warn.tmp"
        rlRun -l "./warn.sh"

    rlPhaseEnd

    rlPhaseStartCleanup
        #rlRun "popd"
        #rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
