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
    rlRun "modprobe scsi_debug delay=0 dev_size_mb=4096 max_queue=1 host_max_queue=1 submit_queues=4"
    sleep 3
    rlRun "lsblk"
    DEV=`ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename`

    for i in $(seq 0 10);do
        rlLog "Execute loop ${i}"
        rlRun "fio --filename=/dev/${DEV} --direct=1 --rw=randrw --bs=4k --iodepth=1 \
            --runtime=100 --numjobs=64 --time_based --name=test --ioengine=libaio \
            --group_reporting=1"
    done

    wait
    sync
    echo 3 > /proc/sys/vm/drop_caches
    sleep 2
    rlRun "modprobe -r scsi_debug"
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
