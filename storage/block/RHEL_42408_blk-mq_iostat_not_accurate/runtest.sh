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
    rlRun "modprobe scsi_debug virtual_gb=250 delay=0"
    sleep 2
    HOSTS=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*)
    HOSTNAME=$(basename ${HOSTS})
# HOST=$(echo ${HOSTNAME} | grep -o -E '[0-9]+')
    SPATH=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/${HOSTNAME}/target*/*/block/*)
    SDISK=$(basename ${SPATH})

    rlLog "Will using ${SDISK} for testing"
    rlRun "iostat -dx /dev/${SDISK} 1 | tee output.log &"
    rlRun "fio -filename=/dev/${SDISK} -bs=4k -rw=write -direct=1 -name=test -thinktime=4ms --runtime=30"
    killall iostat
    wait
    sleep 5
    rlRun "modprobe -r scsi_debug"

# awk -v disk="$SDISK" '$0 ~ disk {util=$NF} END {print util}' output.log
    util=$(awk -v disk="$SDISK" '$0 ~ disk {util=$NF} END {print util}' output.log)
    util_int=$(printf "%.0f" "$util")
    rlLog "util%int: ${util_int}"
    if (( util_int > 5 )); then
        rlFail "test fail"
    else
        rlPass "test pass"
    fi
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
