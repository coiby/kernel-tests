#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
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

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

. $CDIR/../../syzkaller/include.sh || exit 1

chrony_config=/etc/chrony.conf
backup_chrony_config=/root/chrony.conf.bak

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd
    rlPhaseStartTest "Stop syzkaller and get results"
        rlRun syzkaller_stop
        rlRun syzkaller_check_results
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun syzkaller_cleanup
        # Restore date and time in case syscalls changed it
        rlRun "cp $backup_chrony_config $chrony_config"
        rlRun "systemctl restart chronyd"
        sleep 10
        rlRun "chronyc makestep"
        rlLog "Current date and time: $(date '+%d-%m-%y %H:%m:%S')"
        rlRun "rm -f $backup_chrony_config"
    rlPhaseEnd
rlJournalEnd
