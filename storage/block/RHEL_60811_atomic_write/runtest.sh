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

function check_nvme_atomic_support()
{
    get_free_disk nvme
# shellcheck disable=SC2128
    for i in ${disk_list};do
        atomic_support=$(nvme id-ctrl ${i} | grep -E "awun\s*:|awupf\s*:")
        awun=$(echo ${atomic_support} | grep -E "awun\s*:" | awk '{print $NF}')
        awupf=$(echo ${atomic_support} | grep -E "awupf\s*:" | awk '{print $NF}')
        if ([ -n "$awun" ] && [ -n "$awupf" ]) && [ "$awun" -ne 0 ] && [ "$awupf" -ne 0 ];then
            rlLog "device ${i} support atomic write,using it for testing"
            DEV=${i}
            break
        else
            rlLog "device ${i} does not support atomic write,skip it"
        fi
    done

    if [ -z ${DEV} ];then
        rlLog "No suitable nvme device found, skip test"
        rstrnt-report-result "no suitable nvme device found" SKIP 0
        exit 0
    fi
}

function atomic_write_test()
{
    check_nvme_atomic_support
    BLOCK_DEVICE=${DEV}
    rlLog "write data to the block device"
    touch "${CDIR}/write_test_flage"

#    dd if=${DATA_FILE} of=${BLOCK_DEVICE} bs=512 seek=${LBA_START} count=${LBA_COUNT} oflag=direct conv=fsync &
    rlRun "fio --name=write_test atomic_write_test.fio &"
# shellcheck disable=SC2034
    FIO_PID=$!
    sleep 100

    rlLog "manual trigger panic"
    echo "Note: this Call Trace info is trigger by manual,not real issue" | tee /dev/kmsg
    rlRun "echo 1 > /proc/sys/kernel/sysrq"
    rlRun "echo c > /proc/sysrq-trigger"

#    nvme reset ${BLOCK_DEVICE}
#    wait ${FIO_PID}
}

function atomic_verify_test()
{
    rlLog "verify data on the block device"
    rlRun "fio --name=verify_test atomic_write_test.fio"

    rm -rf ${DIR}/write_test_flage
}

function check_atomicity()
{
    rlLog "check data atomicity from block device"
    dd if=${BLOCK_DEVICE} of=${READ_BACK_FILE} bs=512 skip=${LBA_START} count=${LBA_COUNT}
    if cmp -s ${DATA_FILE} ${READ_BACK_FILE};then
        rlPass "Test Pass: Data is completely written"
    elif [ ! -s ${READ_BACK_FILE} ];then
        rlPass "Test Pass: No data was written"
    else
        rlFail "Test Fail: Data write incomplete"
    fi

    rm -rf ${DATA_FILE} ${READ_BACK_FILE} ${DIR}/write_test_flage
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        if [[ -e "${DIR}/write_test_flage" ]];then
            atomic_verify_test
        else
            atomic_write_test
        fi
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
