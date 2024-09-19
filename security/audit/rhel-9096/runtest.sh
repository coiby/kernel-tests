#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/audit/rhel-9096
#   Description: Test for audit deamon starting process on limited audit backlog(rhel-9096)
#   Author: Dennis Li <denli@redhat.com>
#
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
. /usr/share/beakerlib/beakerlib.sh || exit 1
TmpDir=$(pwd)/tmp

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd

    rlPhaseStartTest "disable audit and setup test envirnment"
        if ! [[ -e $TmpDir/reboot ]]; then
            rlRun "systemctl disable auditd" 0
            rlRun "mkdir -p /etc/systemd/system/auditd.service.d" 0
            rlRun "echo -e \"[Service]\\nRestart=no\" > /etc/systemd/system/auditd.service.d/no_restart.conf" 0 "Disable audit auto start"
            rlRun -l "grubby --update-kernel ALL --args=\"audit=1 audit_rate_limit=0 audit_backlog_limit=320 log_buf_len=15M ignore_loglevel printk.devkmsg=on\""
            rlRun "mkdir $TmpDir" 0 "Creating tmp directory"
            rlRun "touch $TmpDir/reboot" && sync
            rhts-reboot
        fi
    rlPhaseEnd

    rlPhaseStartTest "Testing audit deamon start process"
        rlRun "systemctl status auditd" 3 "Audit deamon disabled after reboot"
        rlRun -l "systemctl start auditd" 0 "Audit deamon should start normally"
        journalctl -b -u auditd >> $TmpDir/log
        if grep "Error" $TmpDir/log > /dev/null ; then
            rlLog "Audit deamon failed to start, please check Journal log for error message"
            rlFileSubmit $TmpDir/log journalctl.log
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText