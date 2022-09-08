#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/ftrace/regression/1123102-kernel-panic-in-trace_find_cmdline/runtest.sh
#   Description: This is a regression test case for ftrace bug 1123102
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
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

BUG_INFO="1123102-kernel-panic-in-trace_find_cmdline"
SRC_FILE="ftrace-page-stress.c"
BIN_FILE="page-move-stress"
LOOP_TIMES=${LOOP:-10}
REBOOT_FLAG=/var/1123102_reboot

rlJournalStart
    if [[ "$TMT_REBOOT_COUNT" == "0" || ! -f "${REBOOT_FLAG}" ]]; then
        rlPhaseStartSetup "Setup $BUG_INFO"
            if stat /run/ostree-booted > /dev/null 2>&1; then
                rpm -q gcc || rpm-ostree install -A --idempotent --allow-inactive gcc
            else
                rpm -q gcc || yum -y install gcc
            fi
            rlRun "gcc $SRC_FILE -o $BIN_FILE"
            mount | grep debug || rlRun "mount -t debugfs none /sys/kernel/debug"
        rlPhaseEnd
    fi

    rlPhaseStartTest  "Test $BUG_INFO"
        if [[ "$TMT_REBOOT_COUNT" == "1" || -f "${REBOOT_FLAG}" ]]; then
            tmt-report-result ${BUG_INFO} PASS || rstrnt-report-result ${BUG_INFO} PASS 0
        else
            rlLogInfo "Loop $LOOP_TIMES times,each time 120s"
            while((LOOP_TIMES--));do
                rlWatchdog "./$BIN_FILE" 300
            done
            rlLogInfo "Test pass, the kernel doesn't crash."
        fi
    rlPhaseEnd

    if [[ "$TMT_REBOOT_COUNT" == "0" || ! -f "${REBOOT_FLAG}" ]]; then
        rlPhaseStartCleanup "Cleanup $BUG_INFO"
            rlRun "touch $REBOOT_FLAG"
            rlLogInfo "Restarting ..."
            tmt-reboot || rstrnt-reboot || rhts-reboot
        rlPhaseEnd
    fi
rlJournalEnd
rlJournalPrintText
