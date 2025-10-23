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
    rlRun "rmmod scsi_debug" "0-255"
    rlRun '{
            modprobe scsi_debug tur_ms_to_ready=30000 ptype=1  max_luns=4 dev_size_mb=1000; \
            for i in {0..1}; do mt -f /dev/st${i} status; done; \
            sleep 32; for i in {0..3}; do mt -f /dev/st${i} status; done; \
            modprobe -r scsi_debug
            } 2>&1 | tee output1.log'
    check_result output1.log

    rlRun "rpm -q kernel-devel || yum install -y kernel-devel"
    rlRun "git clone https://gitlab.com/redhat/centos-stream/tests/kernel/storage/mhvtl.git"
    rlRun "cd mhvtl/kernel && make && make install > /dev/null 2>&1"
    rlRun "cd ../ && make && make install > /dev/null 2>&1"
    rlRun "modprobe mhvtl"
    rlRun "systemctl daemon-reload"
    rlRun "systemctl start mhvtl.target"
    rlRun "systemctl status mhvtl.target" "0-255"
    sleep 5
    rlRun "lsscsi -g"

    rlRun '{
            for i in {0..1}; do mt -f /dev/st${i} status; done; sleep 32; \
            for i in {0..3}; do mt -f /dev/st${i} status; done
            } 2>&1 | tee output2.log'
    check_result output2.log

    rlRun "sg_map -st 2>&1 | tee output3.log"
    check_result output3.log

    rlRun "systemctl stop mhvtl.target"
    sleep 5
    rlRun "modprobe -r mhvtl"
    rlRun "lsscsi -g"
    if lsscsi -g | grep -q mediumx;then
        rlRun "systemctl stop mhvtl.target"
    fi
}

function check_result()
{
    if grep -q "Input/output error" $1; then
        rlFail "$1 test failed,please check"
    else
        rlPass "$1 test pass"
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
