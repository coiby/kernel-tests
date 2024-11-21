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

rlJournalStart
    rlPhaseStartSetup
        if [ ! "${TMT_TEST_RESTART_COUNT}" -eq 0 ]; then
            rlRun "userdel -r unprivileged_user"
            rlDie "unprivileged_user rebooted the system"
        fi
        rlRun "useradd unprivileged_user"
    rlPhaseEnd

    rlPhaseStartTest
        # check if user has cap_sys_boot privilege
        if su - unprivileged_user -c "capsh --print | grep \"Current:\" | grep -q cap_sys_boot"; then
            rlRun "userdel -r unprivileged_user"
            rlDie "unprivileged_user has cap_sys_boot privilege"
        fi
        rlLog "trying reboot from unprivileged_user"
        rlRun "su - unprivileged_user -c \"rstrnt-reboot\"" 1 "Expected to fail: unprivileged users should not be able to reboot the system"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "userdel -r unprivileged_user"
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText
