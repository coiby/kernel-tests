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
    if [ -f /etc/multipath.conf ]; then
        rlRun "cp /etc/multipath.conf /tmp/"
        rlRun "rm -rf /etc/multipath.conf"
    fi
    rlRun "mpathconf --enable"
    rlRun "mpathconf"

    get_free_disk ssd
# shellcheck disable=SC2154
    rlLog "will using device ${dev0} for testing"
    DEV="$dev0"
    MP_DEV=""
    rlRun "systemctl status multipathd" "0-255"

cat <<"EOF" >/etc/multipath.conf
defaults {
        user_friendly_names yes
        find_multipaths no
        enable_foreign "^$"
}

blacklist_exceptions {
        property "(SCSI_IDENT_|ID_WWN)"
}

blacklist {
}
EOF

    rlRun "systemctl reload multipathd" "0-255"
    rlRun "systemctl restart multipathd"
    rlRun "systemctl status multipathd" "0-255"
    sleep 10
    rlRun "lsblk"
    rlRun "multipath -ll"

    BN_DEV=$(basename ${DEV})
    MP_DEV=$(multipath -ll | awk -v bn_dev="${BN_DEV}" '/mpath/ {mpath_name=$1} $0 ~ bn_dev {print mpath_name}')
    DM_DEV=$(multipath -ll | awk -v bn_dev="${BN_DEV}" '/mpath/ {mpath_name=$3} $0 ~ bn_dev {print mpath_name}')

    rlRun "echo none > /sys/block/${BN_DEV}/queue/scheduler"
    rlRun "echo none > /sys/block/${DM_DEV}/queue/scheduler"
    rlRun "echo 2 >/sys/block/${BN_DEV}/device/queue_depth"
    rlRun "dd if=/dev/mapper/${MP_DEV} of=/dev/null iflag=direct bs=1G count=1"
    rlRun "iostat -x 1 -p ${BN_DEV} | tee output.log &"
    sleep 20
    killall iostat
    wait

# awk -v disk="$SDISK" '$0 ~ disk {util=$NF} END {print util}' output.log
    util=$(awk -v disk="$BN_DEV" '$0 ~ disk {util=$NF} END {print util}' output.log)
    util_int=$(printf "%.0f" "$util")
    rlLog "util%int: ${util_int}"
    if (( util_int == 100 )); then
        rlFail "test fail"
        rlRun "cat /sys/block/${BN_DEV}/queue/scheduler"
        rlRun "cat /sys/block/${DM_DEV}/queue/scheduler"
        rlRun "cat /sys/block/${BN_DEV}/device/queue_depth"
        rlRun "cat output.log"
    else
        rlPass "test pass"
    fi

}

function cleanup()
{
    rlRun "multipath -F"
    rlRun "systemctl stop multipathd"
    rlRun "mpathconf --disable"
    rlRun "rm -rf /etc/multipath.conf"
    [ -f /tmp/multipath.conf ] && rlRun "cp /tmp/multipath.conf /etc/"
    sleep 5
    rlRun "lsblk"
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        run_test
        cleanup
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
