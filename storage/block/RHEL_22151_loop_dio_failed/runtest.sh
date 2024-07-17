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
    rlRun "modprobe scsi_debug delay=0 sector_size=4096 dev_size_mb=512"
    sleep 3
    rlRun "lsblk"

# figure out scsi_debug disks
    HOSTS=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*)
    HOSTNAME=$(basename "${HOSTS}")
# shellcheck disable=SC2012
    DISK=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename)
    DEV=/dev/${DISK}

    if rlIsRHEL '>=10';then
        rlRun "losetup -f ${DEV} -b 4096 --direct-io=on" "0-255"
    else
        rlRun "losetup -f ${DEV} --direct-io=on" "0-255"
    fi
    rlRun "mkfs.xfs /dev/loop0 2>&1" | tee test.log
    rlRun "cat test.log | grep -i 'pwrite failed'" 1 "if command failed,please check the error"

# clean loop device
    rlRun "losetup -d /dev/loop0"
    sleep 3
    rlRun "rmmod scsi_debug -f"
    rlRun "lsblk"
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        run_test
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
