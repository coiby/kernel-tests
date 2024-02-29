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
. /usr/share/beakerlib/beakerlib.sh     || exit 1

function run_test()
{
    rlRun "rpm -q podman || yum install -y podman"
    if rlIsRHEL '>=9.0';then
        rlRun "rpm -q container-tools || yum install -y container-tools"
    else
        rlRun "rpm -q container-tools || yum module install -y container-tools"
    fi
    sleep 5

    rlLog "The original num_cgroups value:"
    rlRun "cat /proc/cgroups | grep -e subsys -e blkio | column -t"
    num_cgroupsV1=$(cat /proc/cgroups | grep -e subsys -e blkio | column -t | awk 'NR==2 { print $3 }')

    for i in $(seq 1000); do podman run --name=test --replace centos /bin/echo 'running'; done >/dev/null &
    pid=$!

    for ((i=1; i<=10; i++));do
        rlRun "cat /proc/cgroups | grep -e subsys -e blkio | column -t >> num_cgroups.txt"
        sleep 30
    done

    wait $pid

    rlRun "cat num_cgroups.txt"
    my_array=()
    for i in $(cat num_cgroups.txt | awk 'NR%2==0 { print $3 }');do
        my_array+=("$i")
    done

    for item in "${my_array[@]}";do
        if [ "$item" -gt $(("$num_cgroupsV1" + 20)) ];then
            rlFail "Test failed: num_cgroups increase"
        else
            rlPass "Test passed: num_cgroups does not increase"
        fi
    done
}

function check_log()
{
    rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
    rlRun "dmesg | grep 'BUG:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'WARNING:'" 0-255 "check the errors"
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
