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

function scsi_debug__test()
{
    rlRun "modprobe scsi_debug dev_size_mb=4096 nr_queues=2"
    sleep 3
    rlRun "lsblk"

# figure out scsi_debug disks
    HOSTS=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*)
    HOSTNAME=$(basename "${HOSTS}")
# shellcheck disable=SC2012
    DISK=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename)

    run_io
    wait
    sleep 10
    rlRun "rmmod scsi_debug -f"
}

function null_blk_test()
{
    rlRun "modprobe null_blk nr_devices=1 nr_queues=2"
    sleep 3
    rlRun "lsblk"
    DISK=nullb0

    run_io
    wait
    sleep 10
    rlRun "modprobe -r null_blk"
}

function nvme_test()
{
    get_free_disk nvme

# shellcheck disable=SC2154
    rlLog "Get test disk: ${dev0}"
    DISK=$(basename ${dev0})

    run_io
    wait
    sleep 10
}

function run_io()
{
    rlRun "cat /proc/cmdline"
    rlRun "grep Cpus_allowed_list /proc/self/status"
    rlRun "cat /sys/devices/system/cpu/isolated"

    rlRun "echo deadline > /sys/block/${DISK}/queue/scheduler"
    rlRun "numactl -C0,1 fio --filename=/dev/${DISK} --size=10GB --name=test \
        --direct=0 --rw=rw --bs=16K --ioengine=libaio --iodepth=128 --numjobs=8 \
        --time_based --runtime=60 --ioscheduler=mq-deadline > tmp.out 2>&1 &"
    sleep 3

# bpftrace -e 'kprobe:null_queue_rq { @=count() }'
    if [[ ${DISK} == *nvme* ]];then
        timeout -s INT 50 bpftrace -e 'kprobe:nvme_queue_rq{ @[cpu]=count() }' > ${DISK}_count.log
    elif [[ ${DISK} == *null* ]];then
        timeout -s INT 50 bpftrace -e 'kprobe:null_queue_rq{ @[cpu]=count() }' > ${DISK}_count.log
    else
        rlLog "get none disk for testing,please check"
    fi

    sleep 10
    rlRun "cat ${DISK}_count.log"

# ./trace.bt | tee ${DISK}_count.log
    num=`cat ${DISK}_count.log | grep "@" | wc -l`

    if [[ ${num} -ne 2 ]];then
        rlFail "blk-mq kwokers are scheduled on isolated cpus,please check"
    else
        rlPass "no kworkers are run from isolated cpus"
    fi
}

function check_result()
{
    for file in *count.log;do
        num=$(grep -c "@" "$file")

        if [[ ${num} -ne 2 ]]; then
            rlFail "blk-mq kworkers are scheduled on isolated cpus for ${file}, please check"
        else
            rlPass "no kworkers are run from isolated cpus for ${file}"
        fi
    done
}

function tuned_setup()
{
    rlRun "systemctl status tuned" "0-255"
    rlRun "systemctl enable tuned --now"
    rlRun "systemctl restart tuned"
    rlRun "tuned-adm list"

    cpu_num=$(cat /proc/cpuinfo  | grep processor | awk 'END{print}' | awk '{print$3}')
    rlRun "sed -i '/\S/d' /etc/tuned/cpu-partitioning-variables.conf"
    rlRun "echo 'isolated_cores=2-${cpu_num}' > /etc/tuned/cpu-partitioning-variables.conf"

    rlRun "tuned-adm profile cpu-partitioning"
    sleep 3
    rlRun "tuned-adm active"
    rlRun "tuned-adm verify" "0-255"
    rlRun "grep Cpus_allowed_list /proc/self/status"
}

function tuned_cleanup()
{
    rlRun "tuned-adm off"
    rlRun "systemctl stop tuned"
    rlRun "systemctl status tuned" "0-255"
    rlRun "grep Cpus_allowed_list /proc/self/status"
}

function k_param_setup()
{
    key_word="isolcpus"
    cmd_line=$(cat /proc/cmdline)
    if [[ ${cmd_line} == *"${key_word}"* ]];then
        rlLog "successfully add isolcpus into kernel parameter"
    else
        default_kernel=$(grubby --default-kernel)
        cpu_num=$(cat /proc/cpuinfo  | grep processor | awk 'END{print}' | awk '{print$3}')
        param="isolcpus=2-${cpu_num}"
        grubby --args=${param} --update-kernel=${default_kernel}
        dracut -f
        rhts-reboot
    fi
}

function k_param_cleanup()
{
    key_word="isolcpus"
    cmd_line=$(cat /proc/cmdline)
    if [[ ${cmd_line} == *"${key_word}"* ]];then
        default_kernel=$(grubby --default-kernel)
        cpu_num=$(cat /proc/cpuinfo  | grep processor | awk 'END{print}' | awk '{print$3}')
        param="isolcpus=2-${cpu_num}"
        grubby --remove-args=${param} --update-kernel=${default_kernel}
        dracut -f
        rhts-reboot
    else
        rlRun "cat /proc/cmdline"
        rlLog "successfully removed isolcpus kernel parameter"
    fi
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        if [[ -e "${CDIR}/test_done_flage" ]];then
            k_param_cleanup
        else
            k_param_setup
            nvme_test
            null_blk_test
            touch "${CDIR}"/test_done_flage
            k_param_cleanup
        fi
        check_result
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
