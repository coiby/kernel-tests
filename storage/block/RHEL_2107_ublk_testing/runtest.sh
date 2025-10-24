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
    uk_flag=0
    ublk_flag=0
    kernel_version=$(uname -r)
    if [[ ${kernel_version} =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?(-rc[0-9]+)?(\+)?$ ]];then
        rlLog "It's upstream kernel!"
        uk_flag=1
    fi

# if (rlIsRHEL '>=10' || ((${uk_flag} == 1))) && grep -q "CONFIG_BLK_DEV_UBLK=y" "/boot/config-${kernel_version}";then
    if rlIsRHEL '>=10' || [ "${uk_flag}" -eq 1 ];then
# if grep -q "CONFIG_BLK_DEV_UBLK=m" "/boot/config-${kernel_version}";then
        ublk_flag=1
    fi

    if [ "${ublk_flag}" -eq 1 ];then
        rlRun "git clone https://gitlab.com/redhat/centos-stream/tests/kernel/storage/ublksrv.git"
        pushd ublksrv
        rlRun "autoreconf -i && ./configure && make -j 4 && make install > tmp.out 2>&1" "0-255"
        popd

        rlRun "echo 0 > /proc/sys/kernel/io_uring_disabled"
        rlRun "modprobe ublk_drv"
#make test T=all
        rlRun "cd ublksrv"
        rlRun "make test T=null"

        rlRun "make test T=loop"

        rlRun "make test T=generic"

        rlRun "ublk list"
        sleep 100
        rlRun "ublk del -a"
        rlRun "rmmod ublk_drv -f"

        rlRun "echo 2 > /proc/sys/kernel/io_uring_disabled"
        rlRun "modprobe ublk_drv"
# ublk operation will failed when io_uring disabled
        rlRun "ublk list" "0-255"
        sleep 100
        rlRun "ublk del -a" "0-255"
        rlRun "rmmod ublk_drv -f"
        rlRun "echo 0 > /proc/sys/kernel/io_uring_disabled"
    else
        rlLog "ublk drive not enable on this kernel, skip testing"
        rstrnt-report-result "not enable UBLK driver" SKIP 0
        exit 0
    fi
    wait
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
