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
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh    || exit 1
. /usr/share/beakerlib/beakerlib.sh     || exit 1

function run_test()
{
    rlRun "cat /sys/module/sd_mod/parameters/probe"
    paremeter=$(cat /sys/module/sd_mod/parameters/probe)
    if [ "$paremeter" != "sync" ]; then
        add_kernel_option
    elif [ "$paremeter" == "sync" ]; then
        if [ ! -e num.txt ]; then
            rlRun "echo 0 > num.txt"
        fi

        num=$(cat num.txt)

        if [ "$num" -lt 6 ]; then
            rlRun "(cd /dev/disk/by-path && ls -l | grep /s) | awk '{print \$9,\$10,\$11}' | tee order_V\"$num\".txt"
            num=$((num + 1))
            rlRun "echo \"$num\" > num.txt"
            compare_two_text
            rhts-reboot
        fi
    else
        rlRun "cat /sys/module/sd_mod/parameters/probe"
        rlLog "There something wrong,please check"
    fi
}

function compare_two_text()
{
    rlRun "(cd /dev/disk/by-path && ls -l | grep /s) | awk '{print \$9,\$10,\$11}' | tee order_V\"$num\".txt"
    file1=order_V0.txt
    file2=order_V"$num".txt
    if [ "$file1" != "$file2" ]; then
        diff "$file1" "$file2"
        # shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then
            rlPass "Loop \"$num\": the disk order keep consistent"
            rstrnt-report-result "Loop \"$num\"" PASS 0
        else
            rlFail "Loop \"$num\": the disk order are different"
            rlRun "cat order_V0.txt"
            rlRun "cat order_V\"$num\".txt"
            rstrnt-report-result "Loop \"$num\"" FAIL 1
        fi
    fi
}

function add_kernel_option()
{
    rlRun 'grubby --args="sd_mod.probe=sync" --update-kernel=ALL'
    rhts-reboot
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
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
fi
