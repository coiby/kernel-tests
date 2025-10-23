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
CDIR=$(dirname "${FILE}")

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh     || exit 1
. /usr/share/beakerlib/beakerlib.sh         || exit 1

function setup()
{
    for i in $(ls /dev/sd? |awk -F / '{print $3}');do
        n=$(cat /proc/partitions  |awk '{print $4}' |egrep $i |wc -l)
        if [ $n = 1 ];then
            rlLog "$i have no partition"
            SSD=$i
            break
        fi
    done

    for i in $(ls /dev/nvme?n? |awk -F / '{print $3}');do
        n=$(cat /proc/partitions  |awk '{print $4}' |egrep $i |wc -l)
        if [ $n = 1 ];then
            echo "$i have no partition"
            NVME=$i
            break
        fi
    done

#disable multipath
    pidof multipathd &>/dev/null && pkill -9 multipathd
    [ -f /etc/multipath.conf ] && rm -f /etc/multipath.conf



    [ -d blktests ] && rm -rf blktests
    git clone https://gitlab.com/redhat/centos-stream/tests/kernel/storage/blktests.git
    pushd blktests
    make
    echo "TEST_DEVS=(/dev/$NVME /dev/$SSD)" > config
    popd
}

function get_time()
{
    date +"%Y-%m-%d %H:%M:%S"
}

function get_result()
{
    result_dir="blktests/results"
    result_file=$(find $result_dir -type f | egrep "$j/$i$")
    out_bad_file="${result_file}.out.bad"
    out_full_file="${result_file}.full"
    out_dmesg_file="${result_file}.dmesg"
    result="UNTESTED"
    if [[ -n $result_file ]]; then
        res=$(grep "^status" $result_file)
        if [[ $res == *"pass" ]]; then
            result="PASS"
        elif [[ $res == *"fail" ]]; then
            result="FAIL"
            [[ -f $out_bad_file ]] && cat "$out_bad_file"; \
            rstrnt-report-log -l "$out_bad_file"
            [[ -f $out_full_file ]] && cat "$out_full_file"; \
            rstrnt-report-log -l "$out_full_file"
            [[ -f $out_dmesg_file ]] && cat  "$out_dmesg_file"; \
            rstrnt-report-log -l "$out_dmesg_file"
        elif [[ $res == *"not run" ]]; then
            result="SKIP"
        else
            result="OTHER"
        fi
    fi

    echo $result
}

function exists_in_list()
{
    LIST=$1
    DELIMITER=$2
    VALUE=$3
    [[ "$LIST" =~ ($DELIMITER|^)$VALUE($DELIMITER|$) ]]
}

function run_test()
{
    setup
    testgroup="block scsi loop nvme zbd nbd"
    skip_case="block/011 nvme/002 nvme/016 nvme/017"
#testgroup="block"
    for j in $testgroup;do
# shellcheck disable=SC2010
        testcase=$(ls blktests/tests/$j | grep '[0-9]$')
        for i in $testcase;do
            if exists_in_list "$skip_case" " " "$j/$i"; then
                rlLog "skip this case: $j/$i"
                continue
            fi
            rmmod -f scsi_debug > /dev/null 2>& 1
            sleep 5
            pushd blktests
            rlRun "./check $j/$i"
            popd
            result=$(get_result)
            if [[ $result == "PASS" ]]; then
                rstrnt-report-result "$j/$i" PASS 0
            elif [[ $result == "FAIL" ]]; then
                rstrnt-report-result "$j/$i" FAIL 1
            elif [[ $result == "SKIP" || $result == "UNTESTED" ]]; then
                rstrnt-report-result "$j/$i" SKIP 0
            else
                rstrnt-report-result "$j/$i" WARN 2
            fi

        done
    done
}

function check_log()
{
    rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
    rlRun "dmesg | grep -i 'BUG:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
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
