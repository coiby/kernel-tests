#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: TestCaseComment
#   Author: Wang Shu <shuwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
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
. /usr/share/beakerlib/beakerlib.sh || exit 2


#RAMDISK_DIR=${RAMDISK_DIR:-/mnt}
RAMDISK_DEV=${RAMDISK_DEV:-/dev/ram0}
RAMDISK_SIZE=${RAMDISK_SIZE:-}
RAMDISK_PERCENT=${RAMDISK_PERCENT:-75}
RAMDISK_FSTYPE=${RAMDISK_FSTYPE:-ext4}



function ramdisk_mount()
{
    mkdir -p $RAMDISK_DIR
    rlRun "mkfs.$RAMDISK_FSTYPE $RAMDISK_DEV"
    rlRun "mount $RAMDISK_DEV $RAMDISK_DIR"
    mkdir -p /mnt/scratchspace /mnt/testarea /mnt/scratch
}

function ramdisk_setup()
{
    local size;
    local mem_total;
    if [ -f ./RAMDISK_REBOOTFLAG ]; then
        return 0
    fi

    if [ ! -z "$RAMDISK_SIZE" ]; then
        size=$RAMDISK_SIZE
    else
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        size=$(echo "$mem_total / 100 * $RAMDISK_PERCENT" | bc)
    fi

    modinfo brd > /dev/null 2>&1
    if [ $? == 0 ]; then
        # for rhel7, load ramdisk module
        rmmod brd
        rlRun "modprobe brd rd_size=${size}"
        return 0
    fi

    # for rhel6, ramdisk is compiled in kernel
    # CONFIG_BLK_DEV_RAM=y
    rlRun "grubby --args=ramdisk_size=${size} --update-kernel=DEFAULT"
    zipl > /dev/null 2>&1

    touch ./RAMDISK_REBOOTFLAG
    rstrnt-reboot
    sleep 100
}


rlJournalStart
    rlPhaseStartSetup

    rlPhaseEnd

    rlPhaseStartTest
    ramdisk_setup
    if [ ! -z "$RAMDISK_DIR" ]; then
        ramdisk_mount
    fi
    rlPhaseEnd

    rlPhaseStartCleanup

    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
