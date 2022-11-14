#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/misc/reboot-loop
#   Description: Will put the system in a reboot loop and also check
#                for the presence intermittent bugs at boot.
#   Author: William R. Gomeringer <wgomerin@redhat.com>
#
#   Copyright (c) 2022 Red Hat, Inc. All rights reserved.
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

. /usr/bin/rhts-environment.sh
. /usr/share/rhts-library/rhtslib.sh

MAX_REBOOTS="10"
PACKAGE="kernel"
SEARCH="BUG"

var_check()
{
        if [ -n "${TESTARGSC}" ]; then
                COUNT=${TESTARGSC}
        else
                COUNT=$MAX_REBOOTS
        fi

        if [ -n "${TESTARGSS}" ]; then
                STRING=${TESTARGSS}
        else
                STRING=$SEARCH
        fi
}

bug_check()
{
        if [ -f /var/log/dmesg ]; then
            rlRun "grep -w BUG /var/log/dmesg" 1
            RET=$?
        elif [ -x /usr/bin/journalctl ]; then
            rlRun "journalctl --dmesg | grep -w BUG" 1
            RET=$?
        fi
        if [ $RET -eq 0 ]; then
                rlLog "Bug found during boot. Please open a bugzilla to report it."
        else
                rlLog "No bugs found during boot"
        fi
}
rlJournalStart
        rlPhaseStartSetup
                rlAssertRpm $PACKAGE
                rlShowRunningKernel
                var_check
                rlLog "Box has rebooted $REBOOTCOUNT times"
        rlPhaseEnd

        rlPhaseStartTest
                bug_check
        rlPhaseEnd

        rlPhaseStartCleanup
                # show reboot count in Beaker web UI too
                report_result "reboot-count" "PASS" "$REBOOTCOUNT"
                if [ "$REBOOTCOUNT" -lt $COUNT ]; then
                        rhts-reboot
                fi
        rlPhaseEnd

rlJournalPrintText
rlJournalEnd
