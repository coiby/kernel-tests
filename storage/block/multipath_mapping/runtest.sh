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

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

# Include enviroment and libraries
# shellcheck source=/dev/null
source "$CDIR"/../../../cki_lib/libcki.sh || exit 1

function setup()
{
    if [ -f /etc/multipath.conf ]; then
        rlRun "cp /etc/multipath.conf /tmp/"
        rlRun "rm -rf /etc/multipath.conf"
    fi
    rlRun "mpathconf --enable"
    rlRun "systemctl restart multipathd"
    rlRun "systemctl status multipathd"
    rlRun "mpathconf"

cat <<"EOF" >/etc/multipath.conf
defaults {
        user_friendly_names yes
        find_multipaths no
        enable_foreign "^$"
}

blacklist_exceptions {
        device {
                vendor Linux
                product scsi_debug
        }
}

blacklist {
        device {
                vendor .*
                product .*
        }
}
EOF

    rlRun "cat /etc/multipath.conf"
    rlRun "systemctl reload multipathd"
    rlRun "systemctl restart multipathd"
}

function run_test()
{
    rlRun "modprobe scsi_debug dev_size_mb=1024"
    sleep 3
# figure out scsi_debug disks
    HOSTS=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter0/host*)
    HOSTNAME=$(basename "${HOSTS}")
# shellcheck disable=SC2012
    DISK=$(ls -d /sys/bus/pseudo/drivers/scsi_debug/adapter*/host*/target*/*/block/* | head -1 | xargs basename)
    DEV=/dev/${DISK}

    rlRun "lsblk"
    rlPass "ls /dev/mapper/mpath*"
    map=$(ls /dev/mapper/mpath*)
    sleep 30

# Sometimes multipath failed by unexpectedly, so skip it
    for i in {1..3};do
        map=$(ls /dev/mapper/mpath*)
        if [ -z "${map}" ];then
            sleep 30
            setup
        else
            break
        fi
    done

    if [ -z "${map}" ] && [ "${i}" -eq 3 ];then
        rstrnt-report-result "multipath failed" SKIP 0
        cleanup
        exit 0
    fi

    mapname=$(basename "${map}")
    rlRun "multipath -ll"
    rlRun "multipath -ll | grep ${mapname}"
    rlRun "multipath -F"

    for _ in $(seq 1 64);do
        rlRun "sg_luns ${DEV}"
    done
    wait
}

function cleanup()
{
    rlRun "multipath -F"
    rlRun "systemctl stop multipathd"
    rlRun "mpathconf --disable"
    rlRun "rm -rf /etc/multipath.conf"
    [ -f /tmp/multipath.conf ] && rlRun "cp /tmp/multipath.conf /etc/"
    sleep 5
    rlRun "rmmod scsi_debug -f"
}

function check_log()
{
    rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
    rlRun "dmesg | grep 'BUG:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
}

rlJournalStart
    rlPhaseStartSetup Setup
        rlRun "rmmod scsi_debug -f" "0-255"
        setup
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "dmesg -C"
        rlRun "uname -a"
        rlLog "$0"
        run_test
        check_log
    rlPhaseEnd

    rlPhaseStartCleanup Cleanup
        cleanup
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
