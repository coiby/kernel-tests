#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/power-management/turbostat/sanity
#   Description: Confirm turbostat is supported
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

PACKAGE="kernel-tools"

rlJournalStart
        rlPhaseStartSetup
                rlAssertRpm "$PACKAGE"
                rlLog "RUNNING KERNEL: `uname -r`"
                rlRun -l "lscpu"
                #rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
                #rlRun "pushd $TmpDir"
        rlPhaseEnd

        rlPhaseStartTest
                # should cover:
                # --> bz1037706: it does not run at all
                # --> bz1456386: not working on AMD (if run on AMD)
                rlRun "turbostat --out turbo.out 2> turbo.err -- ls" 0 "Running turbostat against 'ls'"
                rlAssertNotGrep "read failed" turbo.err
                rlAssertNotGrep "Input/output error" turbo.err

                # --> bz1466735, bz1466743: it shows only half of CPUs
                NPROC=`nproc`
                NPROC_TURBOSTAT=`perl -ne 'print if $found and /^\d/; $found=1 if /^Core\s+CPU/' < turbo.out | wc -l`
                rlAssertEqual "turbostat sees all CPUs" "$NPROC" "$NPROC_TURBOSTAT"
        rlPhaseEnd

        rlPhaseStartCleanup
                #rlRun "popd"
                #rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
        rlPhaseEnd
rlJournalPrintText
rlJournalEnd
