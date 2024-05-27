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
. "${CDIR}"/../../block/include/include.sh    || exit 1
. /usr/share/beakerlib/beakerlib.sh     || exit 1

function run_test()
{
    get_free_disk ssd
    rlRun "lsscsi -g"
    lsscsi_output=$(lsscsi -g)
    # shellcheck disable=SC2154
    dev_line=$(echo "${lsscsi_output}" | grep "${dev0}")
    host_num=$(echo "${dev_line}" | awk -F '[' '{print $2}' | awk -F ':' '{print $1}')
    dev_name=$(basename "${dev0}")

    rlLog "Will using ${dev0} for testing"
    rlRun "sg_map -sd"
    dev_sg=$(sg_map -sd | grep "${dev0}" | awk -F ' ' '{print $1}')
    rlRun "exec 3<>${dev_sg}"
    rlRun "echo 1 > /sys/block/${dev_name}/device/delete"
    rlRun "exec 3>&-"
    sleep 5
    rlRun "echo '- - -' > /sys/class/scsi_host/host${host_num}/scan"
    rlRun "lsblk"
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
