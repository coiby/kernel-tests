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

function timerlat_setup() {
    # Temporarily stop the timerlat tracing service if it is active (VROOM-23444)
    if systemctl is-active --quiet timerlat_trace; then
        rlLog "'timerlat_trace' service is currently active. Temporarily stopping it to avoid conflicts."
        rlRun "systemctl stop timerlat_trace"
        rlRun "touch /var/tmp/timerlat_trace_stopped"
    else
        rlLog "'timerlat_trace' service is not active. Proceeding with the test."
        rlRun "rm -f /var/tmp/timerlat_trace_stopped"
    fi
}

function timerlat_start() {
    rlRun "tmux new-session -d -s timerlat 'rtla timerlat hist -d \"24h\" -u | tee /var/tmp/timerlat_hist.txt'"
}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        # Increase hung_task_timeout_secs to 300 from 120 to avoid possible hung task crash.
        rlRun "sysctl -w kernel.hung_task_timeout_secs=300"
        # Dont panic if hung task encountered.
        rlRun "sysctl -w kernel.hung_task_panic=0"
        rlRun "cp $chrony_config $backup_chrony_config"
        rlLog "Current date and time: $(date '+%d-%m-%y %H:%m:%S')"
        rlRun syzkaller_setup
        rlRun timerlat_setup
    rlPhaseEnd
    rlPhaseStartTest "Start fuzzing with syzkaller"
        rlRun timerlat_start
        rlRun syzkaller_start
    rlPhaseEnd
    rlPhaseStartCleanup
        # Install glibc-static again, required for functional tests
        pkg_mgr=$(K_GetPkgMgr)
        if [[ $pkg_mgr == "rpm-ostree" ]]; then
            rlRun "rpm-ostree -y --idempotent --allow-inactive install glibc-static"
        else
            rlRun "dnf -y history undo $(dnf history list | grep -m 1 -- '-y remove glibc-static' | awk '{print $1}')"
        fi
    rlPhaseEnd
rlJournalEnd
