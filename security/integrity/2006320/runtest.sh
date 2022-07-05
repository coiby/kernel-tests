#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        grubby --info=DEFAULT
        rlFileSubmit /boot/config-$(uname -r)
        grep 'CONFIG_INTEGRITY=y' /boot/config-$(uname -r) || { echo "integrity subsystem disabled"; rstrnt-report-result $RSTRNT_TASKNAME SKIP; exit 0; }
    rlPhaseEnd

    rlPhaseStartTest check_config
        rlAssertGrep 'CONFIG_IMA_WRITE_POLICY=y' /boot/config-$(uname -r)
    rlPhaseEnd

    rlPhaseStartTest kselftest
        rlRun "yum install -y kernel-selftests-internal"
        rlRun "cd /usr/libexec/kselftests/bpf/"
        for i in {1..5}; do
            rlRun "./test_progs-no_alu32 -t test_ima -vv"
        done
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
