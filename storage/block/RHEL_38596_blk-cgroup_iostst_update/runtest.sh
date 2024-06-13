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

function setup()
{
    [ ! -d /sys/fs/cgroup/t1.slice ] && mkdir /sys/fs/cgroup/t1.slice
    [ ! -d /sys/fs/cgroup/t1.slice/t1-t2.slice ] && mkdir /sys/fs/cgroup/t1.slice/t1-t2.slice
    [ ! -d /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice ] && mkdir /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice
    echo "+io" > /sys/fs/cgroup/cgroup.subtree_control
    echo "+io" > /sys/fs/cgroup/t1.slice/cgroup.subtree_control
    echo "+io" > /sys/fs/cgroup/t1.slice/t1-t2.slice/cgroup.subtree_control
    echo "+io" > /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice/cgroup.subtree_control
    systemd-run --slice t1-t2-t3 dd if=/dev/zero of=/tmp/test bs=4k count=10 oflag=direct
    sleep 5
    rmdir /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice
    rmdir /sys/fs/cgroup/t1.slice/t1-t2.slice
    rmdir /sys/fs/cgroup/t1.slice
}

function run_test()
{
    setup
    show_stat()
    {
        rlLog "$1"
        rlRun "cat /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice/io.stat | grep '$2'" "0-255"
        rlRun "cat /sys/fs/cgroup/t1.slice/io.stat | grep '$2'" "0-255"
    }

    [ ! -d /sys/fs/cgroup/t1.slice ] && mkdir /sys/fs/cgroup/t1.slice
    [ ! -d /sys/fs/cgroup/t1.slice/t1-t2.slice ] && mkdir /sys/fs/cgroup/t1.slice/t1-t2.slice
    [ ! -d /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice ] && mkdir /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice
    echo "+io" > /sys/fs/cgroup/cgroup.subtree_control
    echo "+io" > /sys/fs/cgroup/t1.slice/cgroup.subtree_control
    echo "+io" > /sys/fs/cgroup/t1.slice/t1-t2.slice/cgroup.subtree_control
    echo "+io" > /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice/cgroup.subtree_control

    sleep 3
    get_free_disk ssd
    # shellcheck disable=SC2154
    DEV=${dev0}
    DNAME=`basename ${DEV}`
    MAJMIN=`lsblk | grep ${DNAME} | awk '{print $2}'`
    rlRun "lsblk | grep ${DNAME}"
    show_stat "show io.stat before running dd" ${MAJMIN}
    systemd-run --slice t1-t2-t3 dd if=/dev/zero of=${DEV} bs=4k count=10 oflag=direct
    show_stat "show io.stat after running dd" ${MAJMIN}
    systemd-run --slice t1-t2-t3 dd if=/dev/zero of=${DEV} bs=4k count=10 oflag=direct
    show_stat "show io.stat after running dd" ${MAJMIN}
    systemd-run --slice t1-t2-t3 dd if=/dev/zero of=${DEV} bs=4k count=10 oflag=direct
    show_stat "show io.stat after running dd" ${MAJMIN}

    A=$(cat /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice/io.stat | grep ${MAJMIN} | awk -F " " '{print $5}')
    B=$(cat /sys/fs/cgroup/t1.slice/io.stat | grep ${MAJMIN} | awk -F " " '{print $5}')
    rlLog "A:${A} B:${B}"
    if [  "$A" = "$B" ];then
        rlPass "Test Pass: the iostat updated"
    else
        rlFail "Test Fail: the iostat not update"
    fi

    rmdir /sys/fs/cgroup/t1.slice/t1-t2.slice/t1-t2-t3.slice
    rmdir /sys/fs/cgroup/t1.slice/t1-t2.slice
    rmdir /sys/fs/cgroup/t1.slice
# when test done,please reboot or delecte slice cgroup created
}

function k_param_setup()
{
    key_word="systemd.unified_cgroup_hierarchy"
    cmd_line=$(cat /proc/cmdline)
    if [[ ${cmd_line} == *"${key_word}"* ]];then
        rlLog "successfully add cgroupV2 into kernel parameter"
    else
        default_kernel=$(grubby --default-kernel)
        param="systemd.unified_cgroup_hierarchy=1"
        grubby --args=${param} --update-kernel=${default_kernel}
        dracut -f
        rhts-reboot
    fi
}

function k_param_cleanup()
{
    key_word="systemd.unified_cgroup_hierarchy"
    cmd_line=$(cat /proc/cmdline)
    if [[ ${cmd_line} == *"${key_word}"* ]];then
        default_kernel=$(grubby --default-kernel)
        param="systemd.unified_cgroup_hierarchy=1"
        grubby --remove-args=${param} --update-kernel=${default_kernel}
        dracut -f
        rhts-reboot
    else
        rlRun "cat /proc/cmdline"
        rlLog "successfully removed cgroupV2 kernel parameter"
    fi
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        if [[ -e "${CDIR}/test_done_flage" ]];then
            k_param_cleanup
        else
            if rlIsRHEL 8;then
                k_param_setup
                run_test
                touch "${CDIR}"/test_done_flage
                k_param_cleanup
            else
                run_test
            fi
        fi
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
