#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/power-management/powertop/sanity
#   Description: Confirm powertop is supported
#   Author: Evan McNabb <emcnabb@redhat.com>
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
        #rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        #rlRun "pushd $TmpDir"
    rlPhaseEnd

    rlPhaseStartTest
        # Test 1: Does powertop successfully run on this system? (See BZ 998021)
        rlRun -l "powertop --html --time=5"
        rlRun -l "powertop --csv --time=5"
        # Test 2: Does test run for specified time?
        rlRun -l "./00_set_time.sh"
        # Show the output - it may me needed to interpred fails in further tests
        rlRun -l "cat powertop.csv"
        # Test 3: Does test allow change name of output file?
        rlRun -l "./01_set_filename.sh"
        # Test 4: This tested has checked values in "Top 10 Power Consumers"
        #         But these values aren't utilization, therefore the test was bogus.
        # Test 5: Does test allow change name of output file even for html output?
        rlRun -l "./03_set_filename_html.sh"
        # Test 6: Does test all iterations?
        rlRun -l "./04_multiple_iterations.sh"
    rlPhaseEnd

    rlPhaseStartCleanup
        #rlRun "popd"
        #rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
