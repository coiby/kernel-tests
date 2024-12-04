#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/bz1600394/Regression/bz1600394-Userspace-triggered-crash-in-AF_ALG-aead_recvmsg
#   Description: Userspace-triggered crash in AF_ALG aead_recvmsg
#   Author: Linqing Lu <lilu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "gcc hmac-sha3-repro.c"
        ./a.out 2>&1 | tee output.log
        rlAssertGrep "bind(): No such file or directory\|bind(): Invalid argument" output.log
        rlAssertGrep "setsockopt(): Protocol not available" output.log
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f a.out output.log"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
