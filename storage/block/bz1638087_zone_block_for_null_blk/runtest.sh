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

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh     || exit 1
. /usr/share/beakerlib/beakerlib.sh         || exit 1

function runtest ()
{
    rlRun "modprobe null_blk nr_devices=1 zoned=1 zone_nr_conv=4 zone_size=64"
    sleep 3
    rlRun "dmesg | tail -n 20"
    rlRun "lsblk"
    disk=`lsblk | grep nullb | awk -F ' ' '{print$1}'`
    disk_path=/dev/$disk
    if [ ! $disk ];then
        rlLog "There is no null_blk device, please check"
        exit 1
    else
        rlLog "Disk Path: $disk_path"
    fi

    rlRun "blkzone report $disk_path"

    rlRun "rmmod null_blk"
}

function check_log()
{
    rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
    rlRun "dmesg | grep -i 'BUG:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
}

rlJournalStart
    rlPhaseStartSetup
        rlRun "uname -a"
        rlLog "$0"
        rlRun "modprobe sg"
    rlPhaseEnd

    rlPhaseStartTest
        runtest
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
