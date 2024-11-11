#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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
# Wrapper script for watchdog API fuzzing test using syzkaller.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

export TEST=watchdog-fuzzing-test

rlJournalStart
    rlPhaseStartSetup
        rlRun "gcc src/feed_watchdog.c -o feed_watchdog"
        rlRun ./feed_watchdog 0,143 & # Feed watchdog during test, expect it to be killed
    rlPhaseEnd
    rlPhaseStartTest "Run syzkaller with watchdog API"
        pushd ../../memory/mmra/syzkaller
        rlRun "bash ./runtest.sh"
        popd
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "killall feed_watchdog"
        # Magic close to disable watchdog and avoid rebooting on further tests
        # https://www.kernel.org/doc/Documentation/watchdog/watchdog-api.txt
        rlRun "echo 'V' > /dev/watchdog"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
