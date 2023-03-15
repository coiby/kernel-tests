#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/microcode/sanity
#   Description: Microcode Sanity Check
#   Author: Rachel Sibley <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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

# Set the full test name
TEST="/kernel/microcode/sanity"

rlJournalStart
    rlPhaseStartTest
        # Reinstall the pkgs to ensure no errors are seen
        if rlIsRHEL >= 7 && lscpu | grep -q AMD; then
            rlRun -l "yum -y remove linux-firmware"
            rlRun -l "yum -y install linux-firmware"
        else
            rlRun -l "yum -y remove microcode_ctl"
            rlRun -l "yum -y install microcode_ctl"
        fi
    rlPhaseEnd

    rlPhaseStartTest
        # Disable microcode service, restore to previous state
        if rlIsRHEL >= 7; then
            rlServiceStop microcode
            rlServiceDisable microcode
            rlServiceRestore microcode
            rlRun -l "systemctl daemon-reload"
            rlRun -l "systemctl status microcode -l | egrep -i 'error|fail|warn'" 1
        fi
    rlPhaseEnd

    rlPhaseStartTest
        # Grep the Logs for microcode errors
        if rlIsRHEL >= 7; then
            # Display microcode related errors
            rlRun -l "grep -i microcode /var/log/messages > /tmp/error.log"
            rlAssertNotGrep "error|fail|warn" /tmp/error.log -i
            # Display any other related failures that Microcode might have caused
            rlRun -l "journalctl -b -p err"
        fi
    rlPhaseEnd

    rlPhaseStartTest
       # Ensure /proc/cpuinfo matches version printed in logs
       # TODO: Add case for AMD
        if lscpu | grep -q Intel; then
            cpuinfo_ver=$(cat /proc/cpuinfo | grep -m1 microcode | awk '{print $3;}')
            log_ver=$(cat /var/log/messages | grep -i -m1 'microcode.*revision=' | cut -d '=' -f4)
            if [[ "$cpuinfo_ver" == "$log_ver" ]]; then
                rlLog "Versions match; /proc/cpuinfo is $cpuinfo_ver compared to $log_ver displayed in logs"
            else
                # Display an error about the mismatched version
                rlFail "Versions do not match; /proc/cpuinfo is $cpuinfo_ver compared to $log_ver displayed in logs"
            fi
        fi
    rlPhaseEnd

rlJournalEnd
# Print the test report
rlJournalPrintText

