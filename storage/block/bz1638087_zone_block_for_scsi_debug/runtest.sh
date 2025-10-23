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

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "${FILE}")

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh     || exit 1
. /usr/share/beakerlib/beakerlib.sh         || exit 1

function setup ()
{
    rlRun "git clone https://gitlab.com/redhat/centos-stream/tests/kernel/storage/libzbc.git"
    rlRun "pushd libzbc"
    rlRun "sh ./autogen.sh;./configure --with-test;make;make install"
    rlRun "popd"
}

function runtest ()
{
    rlRun "modprobe scsi_debug max_luns=1 sector_size=4096 dev_size_mb=16384 zbc=managed zone_size_mb=64 zone_nr_conv=32"
    sleep 3
    rlRun "dmesg | tail -n 20"
    rlRun "lsblk"
    rlRun "lsscsi -g"
    disk_path=`lsscsi -g | grep zbc | awk -F ' ' '{print $6}'`
    sg_path=`lsscsi -g | grep zbc | awk -F ' ' '{print $7}'`
    if [ ! $disk_path ] || [ ! $sg_path ];then
        rlLog "There is no zbc device, please check"
        exit 1
    else
        rlLog "Disk Path: $disk_path  ,Sg Path: $sg_path"
    fi

    rlRun "zbc_info $sg_path"
    rlRun "sg_rep_zones $disk_path"
    rlRun "zbc_report_zones $sg_path"
    rlRun " ./libzbc/test/zbc_test.sh $sg_path"

    rlRun "rmmod scsi_debug"
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
        setup
    rlPhaseEnd

    rlPhaseStartTest
        runtest
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
