#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/drivers/mei/sanity
#   Description: MEI Sanity Check
#   Author: William R. Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
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

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ./kvercmp.sh || exit 1

# Set the full test name
TEST="/kernel/drivers/mei/sanity"

# Create symbolic link to /dev/mei
rlJournalStart
    # Run mei-amt-version test on kernel 3.10.0-352 and older (uses /dev/mei)
    # Run mei-amt-check test on kernel 3.10.0-353 and newer (uses /dev/mei0)
    #   [misc] mei: move from misc to char device
    #   https://gitlab.com/redhat/rhel/src/kernel/rhel-7/-/commit/dcb23f671cd0
    #
    # mei-amt-version is found in kernel's Documentation/misc-devices/mei
    # mei-amt-check is from https://github.com/mjg59/mei-amt-check
    rlPhaseStartSetup
        rlRun "modprobe mei_me" 0 "Load mei_me driver"
        rlAssertRpm gcc
        kvercmp "$(uname -r)" "3.10.0-352.el7"
        if [ $kver_ret -le 0 ]; then
            rlRun -l "gcc -o mei-amt-version mei-amt-version.c"
            rlRun "MEI=./mei-amt-version"
        else
            rlRun -l "gcc -o mei-amt-check mei-amt-check.c"
            rlRun "MEI=./mei-amt-check"
        fi
    rlPhaseEnd

    # Verify no errors are generated in logs
    rlPhaseStartTest
        rlRun -l "$MEI"
        if [ -x /usr/bin/journalctl ]; then
            rlRun "journalctl --dmesg | grep -i mei > /tmp/error.log" 0,1
        else
            rlRun "grep -i mei /var/log/dmesg > /tmp/error.log"
        fi
        rlAssertNotGrep "error|fail|warn" /tmp/error.log -i
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText
