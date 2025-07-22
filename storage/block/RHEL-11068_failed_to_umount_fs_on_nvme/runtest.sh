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
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh    || exit 1
. /usr/share/beakerlib/beakerlib.sh     || exit 1

function run_test()
{
    get_free_disk nvme
    [ ! -d /mnt/ext4 ] && mkdir /mnt/ext4
    # shellcheck disable=SC2154
    rlRun "mkfs.ext4 -F ${dev0}"
    rlRun "mount ${dev0} /mnt/ext4"
    rlRun "dd if=/dev/zero of=/mnt/ext4/file.img &"
    dd_pid=$!
    sleep 30
    disk=$(basename ${dev0})
#    rlRun "echo 1 > /sys/block/${disk}/device/device/remove"
    nvme_pci_id=$(get_nvme_pci_id "$disk")
    rlRun "echo 1 > /sys/bus/pci/devices/${nvme_pci_id}/remove"
    sleep 120
    rlRun "umount /mnt/ext4"
    rlRun "cat /proc/${dd_pid}/stack" 1 "please check the error"
    rlRun "lsblk | grep ${disk}" 1 "disk already removed"

    rlRun "rm -rf /mnt/ext4"
    rlRun "echo 1 > /sys/bus/pci/rescan"
    sleep 5
    rlRun "echo 1 > /sys/bus/pci/rescan"
    rlRun "lsblk | grep ${disk}"
    rlRun "dd if=/dev/zero of=${dev0} bs=4k count=10000"
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
