#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/misc/rtc-hwclock
#   Description: Test RTC using hwclock
#   Author: Erico Nunes <ernunes@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

# Include rhts environment

. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm util-linux

        # Preserve localtime/utc previous setting
        if grep -q LOCAL /etc/adjtime
        then
            HWCLOCK_ARG='--localtime'
        else
            HWCLOCK_ARG='--utc'
        fi
    rlPhaseEnd

    rlPhaseStartTest
        echo 'read RTC'
        rlRun "hwclock --verbose --utc --set --date='2017-02-18 06:07:08'"

        echo 'set non-DST UTC'
        rlRun "hwclock --verbose --utc --set --date='2017-02-18 06:07:08'"
        echo 'set DST UTC'
        rlRun "hwclock --verbose --utc --set --date='2017-05-18 06:07:08'"

        echo 'set non-DST (implied UTC)'
        rlRun "hwclock --verbose --set --date='2017-02-18 06:07:08'"
        echo 'set (implied UTC)'
        rlRun "hwclock --verbose --set --date='2017-05-18 06:07:08'"

        echo 'set non-DST localtime'
        rlRun "hwclock --verbose --localtime --set --date='2017-07-19 08:07:04'"
        echo 'set DST localtime'
        rlRun "hwclock --verbose --localtime --set --date='2017-01-19 08:07:04'"

        echo 'set non-DST (implied localtime)'
        rlRun "hwclock --verbose --set --date='2017-07-19 08:07:04'"
        echo 'set DST (implied localtime)'
        rlRun "hwclock --verbose --set --date='2017-01-19 08:07:04'"
    rlPhaseEnd

    rlPhaseStartCleanup
        # Restore correct time
        rlServiceStop chronyd
        rlRun "chronyd -q 'pool clock.redhat.com iburst'"
        rlServiceStart chronyd
        rlRun "hwclock $HWCLOCK_ARG --systohc"
    rlPhaseEnd

    rlJournalPrintText
rlJournalEnd
