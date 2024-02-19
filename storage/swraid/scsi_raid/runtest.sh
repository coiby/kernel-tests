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
# shellcheck disable=SC2034
TEST=${RSTRNT_TASKNAME}

# Include enviroment and libraries
source /usr/share/beakerlib/beakerlib.sh || exit 1

function create_raid()
{
        case $R in
                raid0)
                        # shellcheck disable=SC2154
                        rlRun -l "lvcreate --type raid0 --stripesize 64k -i 3 \
                                -n non_synced_primary_raid_3legs_1 -L 1G \
                                black_bird $dev0:0-300 $dev1:0-300 \
                                $dev2:0-300 $dev3:0-300"
                        ;;
                raid1)
                        rlRun -l "lvcreate --type raid1 -m 3 -n non_synced_primary_raid_3legs_1 \
                                -L 1G black_bird $dev0:0-300 $dev1:0-300 \
                                $dev2:0-300 $dev3:0-300"
                        ;;
                raid5)
                        rlRun -l "lvcreate --type raid5 -i 3 -n non_synced_primary_raid_3legs_1 \
                                -L 1G black_bird $dev0:0-300 $dev1:0-300 \
                                $dev2:0-300 $dev3:0-300"
                        ;;
                raid10)
                        rlRun -l "lvcreate --type raid10 -i 2 -m 1 \
                                -n non_synced_primary_raid_3legs_1 -L 1G black_bird \
                                $dev0:0-300 $dev1:0-300 $dev2:0-300 \
                                $dev3:0-300"
        esac
}

function setup()
{
        for i in {0..3};do
            rlRun -l "dd if=/dev/zero bs=1M count=2000 of=file$i.img"
            sleep 1
            device=$(rlRun -l "losetup -fP --show file$i.img")
            devices+=" $device"
            eval "dev$i=$device"
            sleep 1
            rlRun -l "mkfs -t xfs -f $device"
            rlRun -l "lsblk"
        done

        rlLog "dev list: $dev0 ,$dev1 ,$dev2 ,$dev3"
        rlRun -l "pvcreate -y $devices"
        rlRun -l "vgcreate  black_bird $devices"
        rlRun -l "pvdisplay"
        rlRun -l "vgdisplay"
}

function cleanup()
{
        rlRun -l "vgremove black_bird"
        rlRun -l "pvremove $devices"
        rlRun -l "losetup -d $devices"
        rlRun -l "rm -rf file*"
        rlRun -l "lsblk"
}

function run_test()
{
        rlLog "Create $R"
        create_raid
        rlRun -l "lsblk"
        rlRun -l "lvdisplay"
        rlRun -l "lvremove /dev/black_bird/non_synced_primary_raid_3legs_1 -y"

}

function check_log()
{
        rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
}

rlJournalStart
    rlPhaseStartSetup
        rlRun -l "dmesg -C"
        rlRun -l "uname -a"
        rlLog "$0"
        setup
    rlPhaseEnd
    for R in raid0 raid1 raid5 raid10;do
        rlPhaseStartTest "$R"
            run_test
        rlPhaseEnd
    done
    rlPhaseStartCleanup
        cleanup
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
