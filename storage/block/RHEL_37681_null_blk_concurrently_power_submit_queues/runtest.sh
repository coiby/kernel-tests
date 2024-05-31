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
    MNT="/sys/kernel/config/nullb/nullb0"
    rlRun "modprobe null_blk nr_devices=0"
    sleep 3
    [ ! -d ${MNT} ] && mkdir -p ${MNT}
    rlRun "pushd ${MNT}"

#    trap 'kill ${PID1} ${PID2}' TERM
#    (sleep 10m; kill -s TERM $$) &

    while true; do echo 1 > submit_queues; echo 4 > submit_queues; done &
    PID1=$!
    while true; do echo 1 > power; echo 0 > power; done &
    PID2=$!

    sleep 10m
    kill -9 ${PID1} ${PID2}
    wait
    echo 1 > submit_queues
    echo 1 > power
    rlRun "popd"
    rlRun "rmmod null_blk" "0-255"
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
