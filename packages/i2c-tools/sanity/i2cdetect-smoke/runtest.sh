#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/i2c-tools/Sanity/i2cdetect-smoke
#   Description: Loads i2c-dev module, and checking if there are devices active in the board.
#   Author: Lukas Zachar <lzachar@redhat.com>
#   Contributor: Michael Menasherov <mmenashe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2012 Red Hat, Inc. All rights reserved.
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
        rlShowRunningKernel
        TmpDir=$(mktemp -d)
        rlRun "touch $TmpDir/list.txt $TmpDir/adapter_info.txt" 0 "Creating 2 temp files"
        rlRun "modprobe i2c-dev" 0 "Loading I2C kernel module"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "ls /sys/class/i2c-dev/ > $TmpDir/list.txt 2>/dev/null"
        if [ -s "$TmpDir/list.txt" ]; then
            rlLog "I2C adapters found, reading information."
            while read -r line; do
                rlRun "cat /sys/class/i2c-dev/$line/name >> $TmpDir/adapter_info.txt 2>/dev/null" 0 "Reading bus name"
                rlRun "cat /sys/class/i2c-dev/$line/dev >> $TmpDir/adapter_info.txt 2>/dev/null" 0 "Reading bus address"
            done < $TmpDir/list.txt
            if [ -s "$TmpDir/adapter_info.txt" ]; then
                rlLog "Bus names and address."
                rlRun "cat $TmpDir/adapter_info.txt"
            else
                rlLogWarning "adapter_info.txt is empty,please check."
            fi
        else
            rlLogWarning "I2C detection failed or no buses available,please check."
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "modprobe -r i2c-dev"
        rlRun "rm -rf \"$TmpDir\"" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
