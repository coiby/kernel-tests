#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/crypto/2174928
#   Description: Test for BZ#2174928 (Note: test will enable FIPS mode, and should be append to the last test to execute if combinding with other tests)
#   Author: Dennis Li <denli@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
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
. /usr/share/beakerlib/beakerlib.sh || exit 1
TmpDir=./tmp

rlJournalStart
    rlPhaseStartSetup
        if rlIsRHEL 7; then
            CFLAGS="-std=c99"
        fi

        rlShowRunningKernel
        rlRun "mkdir $TmpDir" 0 "Creating tmp directory"
        rlRun "cp repro.c repro.c $TmpDir"
        rlRun "pushd $TmpDir"
        rlRun "gcc repro.c $CFLAGS -o repro"
        rlRun "touch result.log"
    rlPhaseEnd

    rlPhaseStartTest "detect unlock balance"
        rlRun "./repro &"
        PID=$!
        rlWatchdog "strace -o result.log -p $PID" 5
        rlRun "grep -q SIGCHLD result.log" 0
        if [ $? -eq 0 ]; then
            rlPass "Fork child process successful, No unbalanced lock detected."
        else
            rlRun "sleep 300"
            rlFail "No child process created, Unbalanced lock, check process hung in dmesg."
        fi
    rlPhaseEnd
    rlPhaseStartCleanup
        rlFileSubmit result.log
        rlFileSubmit dmesg
        rlRun "kill $PID"
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText