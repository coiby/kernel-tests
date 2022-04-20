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

# TEST is required for beakerlib tests
TEST=${RSTRNT_TASKNAME}

# Include enviroment and libraries
source /usr/share/beakerlib/beakerlib.sh || exit 1

function create_raid()
{
        case $R in
                raid0)
                        rlRun "lvcreate --type raid0 --stripesize 64k -i 3 \
                                -n non_synced_primary_raid_3legs_1 -L 1G \
                                black_bird /dev/loop0:0-300 /dev/loop1:0-300 \
                                /dev/loop2:0-300 /dev/loop3:0-300"
                        ;;
                raid1)
                        rlRun "lvcreate --type raid1 -m 3 -n non_synced_primary_raid_3legs_1 \
                                -L 1G black_bird /dev/loop0:0-300 /dev/loop1:0-300 \
                                /dev/loop2:0-300 /dev/loop3:0-300"
                        ;;
                raid5)
                        rlRun "lvcreate --type raid5 -i 3 -n non_synced_primary_raid_3legs_1 \
                                -L 1G black_bird /dev/loop0:0-300 /dev/loop1:0-300 \
                                /dev/loop2:0-300 /dev/loop3:0-300"
                        ;;
                raid10)
                        rlRun "lvcreate --type raid10 -i 2 -m 1 \
                                -n non_synced_primary_raid_3legs_1 -L 1G black_bird \
                                /dev/loop0:0-300 /dev/loop1:0-300 /dev/loop2:0-300 \
                                /dev/loop3:0-300"
        esac
}

function run_test()
{
        for i in {0..3};do
            rlRun "dd if=/dev/zero bs=1M count=2000 of=file$i.img"
            rlRun "losetup -fP file$i.img"
            sleep 1
            rlRun "mkfs -t xfs -f /dev/loop$i"
            rlRun "lsblk"
        done

        rlRun "pvcreate -y /dev/{loop0,loop1,loop2,loop3}"
        rlRun "vgcreate  black_bird /dev/{loop0,loop1,loop2,loop3}"
        rlRun "pvdisplay"
        rlRun "vgdisplay"

        for R in raid0 raid1 raid5 raid10;do
                rlLog "Create $R"
                create_raid
                rlRun "lsblk"
                rlRun "lvdisplay"
                rlRun "lvremove /dev/black_bird/non_synced_primary_raid_3legs_1 -y"
        done

        rlRun "vgremove black_bird"
        rlRun "pvremove /dev/{loop0,loop1,loop2,loop3}"
        rlRun "losetup -d /dev/{loop0,loop1,loop2,loop3}"
        rlRun "rm -rf file*"
        rlRun "lsblk"
}

function check_log()
{
        rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
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
