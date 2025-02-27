#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
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
. ../../cmdline_helper/libcmd.sh || exit 1


rlJournalStart
    if [ "${REBOOTCOUNT}" -eq 0 ]; then
        rlPhaseStartSetup "Adding cmdline parameters"
            rlShowRunningKernel
            rlRun "change_cmdline 'undefined_test=0 no_values_test undefined.test=0 no.values.test'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
    if [ "${REBOOTCOUNT}" -eq 1 ]; then
        rlPhaseStartTest "Parsing for parameters"
            rlRun "journalctl -k | grep -q 'Unknown kernel command line parameters \".*undefined_test=0.*\", will be passed to user space.'"
            rlRun "journalctl -k | grep -q 'Unknown kernel command line parameters \".*no_values_test.*\", will be passed to user space.'"
            rlAssertGrep "undefined_test=0" /proc/cmdline
            rlAssertGrep "no_values_test" /proc/cmdline
            rlAssertGrep "undefined\.test=0" /proc/cmdline
            rlAssertGrep "no\.values\.test" /proc/cmdline
            rlAssertGrep "no_values_test" /proc/1/cmdline
            rlAssertGrep "undefined_test=0" /proc/1/environ
            rlAssertNotGrep "no\.values\.test" /proc/1/cmdline
            rlAssertNotGrep "undefined\.test=0" /proc/1/environ
        rlPhaseEnd
        rlPhaseStartCleanup "Removing cmdline parameters"
            rlRun "change_cmdline '-undefined_test no_values_test undefined.test=0 no.values.test'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
rlJournalEnd
rlJournalPrintText
