#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/misc/set-hwclock
#   Description: Set the hardware RTC clock
#   Author: Jeff Bastian <jbastian@redhat.com>
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

# Include rhts environment

. /usr/share/beakerlib/beakerlib.sh || exit 1

TIME_SERVER=${TIME_SERVER:-time.nist.gov}

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm chrony
        rlAssertRpm util-linux
        # Set current time using NTP
        rlServiceStop chronyd
        rlRun "chronyd -q \"pool $TIME_SERVER iburst\""
        rlServiceStart chronyd
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Current system clock: $(date)"
        rlLog "(Before) Current hardware clock: $(hwclock)"
        rlLog "Setting clock with hwclock --systohc"
        rlRun "hwclock --systohc" 0
        rlLog "(After) Current hardware clock: $(hwclock)"

        rlRun "dmesg > /tmp/dmesg.out" 0 "Print dmesg info"
        rlFileSubmit "/tmp/dmesg.out"
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
