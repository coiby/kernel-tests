#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

# Include enviroment and libraries
. /usr/share/beakerlib/beakerlib.sh     || exit 1

function run_test()
{
    rlRun "modprobe null_blk nr_devices=0"
    rlRun "cd /sys/kernel/"
    rlRun "mkdir config/nullb/nullb0"
    rlRun "echo 1 > config/nullb/nullb0/memory_backed"
    rlRun "echo 4096 > config/nullb/nullb0/blocksize"
    rlRun "echo 20480 > config/nullb/nullb0/size"
    rlRun "echo 1 > config/nullb/nullb0/queue_mode"
    rlRun "echo 1 > config/nullb/nullb0/power" 1 "##Expected 1"
    rlRun "dmesg | grep -i 'legacy IO path is no longer available'"
}

function check_log()
{
    rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
    rlRun "dmesg | grep 'BUG:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
}

rlJournalStart
    rlPhaseStartTest
        rlRun "dmesg -C"
        rlRun "uname -a"
        rlLog "$0"
        run_test
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
