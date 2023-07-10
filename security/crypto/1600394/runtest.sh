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
. ../../../cki_lib/libcki.sh

rlJournalStart
    rlPhaseStartSetup
        if [ "$(rlIsRHEL 7)" ]; then
            rlRun "yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
        fi
        if ! cki_is_kernel_automotive; then
            rlRun "yum install -y python3"
        fi
        rlRun "ls -l /usr/bin/python3*"
    rlPhaseEnd

    rlPhaseStartTest
        rlWatchdog "sudo -u test python3 algtest.py" 600
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
