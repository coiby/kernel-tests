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
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "${FILE}")
. "${CDIR}"/../include/include.sh    || exit 1
. /usr/share/beakerlib/beakerlib.sh     || exit 1

function run_test()
{
    rlRun "modprobe -r scsi_debug" "0-255"
    rlRun "modprobe scsi_debug"
    sleep 2
    HOSTS=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*)
    HOSTNAME=$(basename ${HOSTS})
# HOST=$(echo $HOSTNAME | grep -o -E '[0-9]+')
    SPATH=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/${HOSTNAME}/target*/*/block/*)
    SDISK=$(basename ${SPATH})

    rlRun 'echo "blocked" >/sys/block/${SDISK}/device/state'
    rlLog "Running dd test"
    (dd if=/dev/${SDISK} of=/home/t.log bs=1M count=5;sync) &
    sleep 10
    rlRun 'echo "running" >/sys/block/${SDISK}/device/state'
# dd should finish this work after step 3, unfortunately, still hung.

    sleep 10
    if pidof dd > /dev/null;then
        rlFail "test failed,please check"
    else
        rlPass "test passed"
    fi
    sleep 2
    rlRun "modprobe -r scsi_debug"
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
