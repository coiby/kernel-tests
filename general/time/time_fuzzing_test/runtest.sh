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
# Wrapper script for time-fuzzing-test using syzkaller.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

export TEST=time-fuzzing-test
chrony_config=/etc/chrony.conf
backup_chrony_config=/root/chrony.conf.bak
current_date=''

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        rlRun "cp $chrony_config $backup_chrony_config"
        current_date=$(date '+%d-%m-%y %H:%m:%S')
        rlLog "current date and time : $current_date"
    rlPhaseEnd
    rlPhaseStartTest
        pushd ../../../memory/mmra/syzkaller
        rlRun "bash ./runtest.sh"
        popd
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "cp $backup_chrony_config $chrony_config"
        rlRun "systemctl restart chronyd"
        sleep 10
        rlRun "chronyc makestep"
        current_date=$(date '+%d-%m-%y %H:%m:%S')
        rlLog "current date and time : $current_date"
        rlRun "rm -f $backup_chrony_config"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
