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

function run_fio()
{
    device=$1
    engine=$2
    sched=$3
    pattern=$4
    is_direct=$5
    depth=$6
    fstype=$7
    mnt=$8
    dev=/dev/${device}

    echo "Dev: ublk-${R}  Engine: ${engine} Sched: ${sched} Pattern: ${pattern} " \
        "Depth: ${depth} Fstype: ${fstype}" | tee /dev/kmsg

    if [[ ${fstype} == "xfs" ]];then
        mkfs -t "${fstype}" -f "${dev}"
    else
        mkfs -t "${fstype}" -F "${dev}"
    fi
    mount "${dev}" "${mnt}"
    sleep 3

    rlRun "fio --bs=4k --ioengine=${engine} --iodepth=${depth} --numjobs=8 \
        --rw=${pattern} --name=ublk-${R}-${engine}-${fstype} \
        --filename=${mnt}/test.img --direct=${is_direct} --size=10G \
        --runtime=30 --group_reporting &> /dev/null"
    wait
    sync
    echo 3 > /proc/sys/vm/drop_caches

    rm -rf "${mnt:?}/"*
    umount "${mnt}"
    sleep 3
}

function fio_test()
{
    device='ublkb0'
    is_direct='1'
    pattern='randrw'

    MNT='/mnt/ublk_test'
    [ ! -d ${MNT} ] && mkdir ${MNT}

    for engine in libaio io_uring; do
        for sched in `sed 's/[][]//g' /sys/block/${device}/queue/scheduler`; do
            echo ${sched} > /sys/block/${device}/queue/scheduler
            for depth in 4 128; do
                for fstype in ext2 ext3 ext4 xfs; do
                    run_fio ${device} ${engine} ${sched} ${pattern} ${is_direct} ${depth} ${fstype} ${MNT}
                done
            done
        done
    done
}

function run_test()
{
    # shellcheck disable=SC2034
    if ! output=$(ls /dev/ublk-control); then
        rlLog "not load ublk module,skip UBLK test"
        rstrnt-report-result "not enable UBLK driver" SKIP 0
        exit 0
    fi

# ublk-null not support data io

    case ${R} in
        loop)
                rlRun "dd if=/dev/zero bs=1M count=20000 of=ublk_loop.img"
                rlRun "ublk add -t loop -f ublk_loop.img"
                rlRun "lsblk"
                rlRun "ublk list"
                fio_test
                rlRun "ublk del -a"
                rlRun "rm -rf ublk_loop.img"
                rlRun "lsblk"
                ;;
        qcow2)
                rlRun "qemu-img create -f qcow2 ublk_qcow2.qcow2 20G"
                rlRun "ublk add -t qcow2 -f ublk_qcow2.qcow2"
                rlRun "lsblk"
                rlRun "ublk list"
                fio_test
                rlRun "ublk del -a"
                rlRun "rm -rf ublk_qcow2.qcow2"
                rlRun "lsblk"
                ;;
        nvme)
                get_free_disk nvme
                # shellcheck disable=SC2154
                rlRun "parted -s ${dev0} mklabel gpt mkpart primary 1M 60G"
                rlRun "ublk add -t loop -f ${dev0}p1"
                rlRun "lsblk"
                rlRun "ublk list"
                fio_test
                rlRun "ublk del -a"
                rlRun "parted -s ${dev0} rm 1"
                rlRun "lsblk"
                ;;
        ssd)
                get_free_disk ssd
                # shellcheck disable=SC2154
                rlRun "parted -s ${dev0} mklabel gpt mkpart primary 1M 60G"
                rlRun "ublk add -t loop -f ${dev0}1"
                rlRun "lsblk"
                rlRun "ublk list"
                fio_test
                rlRun "ublk del -a"
                rlRun "parted -s ${dev0} rm 1"
                rlRun "lsblk"
    esac
}

rlJournalStart
    rlPhaseStartTest
        rlRun "dmesg -C"
        rlRun "uname -a"
        rlLog "$0"
        run_test
    rlPhaseEnd
    for R in loop qcow2 nvme ssd;do
        rlPhaseStartTest "$R"
            run_test
        rlPhaseEnd
    done
    rlPhaseStartCleanup
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
