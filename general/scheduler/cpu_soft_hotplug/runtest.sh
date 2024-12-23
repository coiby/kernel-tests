#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/cpu_soft_hotplug
#   Description: cpu online offline test
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

. /usr/share/beakerlib/beakerlib.sh ||  exit 1

if [ -z "$OUTPUTFILE" ]; then
	export OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`
fi

origin_nr_cpus=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)
last_cpu=$((origin_nr_cpus - 1))

declare -A cpu_online_stats

function cpu_offline()
{
        local i
        local stat

        for i in $(seq 1 $last_cpu); do
                rlRun "echo 0 > /sys/devices/system/cpu/cpu$i/online" 0-255
                stat="$(cat /sys/devices/system/cpu/cpu$i/online)"
                [ "$stat" -ne "0" ] && echo cpu$i busy
        done
}

function cpu_online()
{
        local i
        local stat

        for i in $(seq 1 $last_cpu); do
                rlRun "echo 1 > /sys/devices/system/cpu/cpu$i/online"
                stat="$(cat /sys/devices/system/cpu/cpu$i/online)"
                rlAssertEquals "cpu oneline status restore: expect==actual" "1" "$stat"
        done
}

rlJournalStart
        rlPhaseStartSetup
                rlLogInfo "This test covers bz2024869"
                for i in $(seq 1 $last_cpu); do
                        cpu_online_stats["$i"]=$(cat /sys/devices/system/cpu/cpu$i/online)
                        rlLog "cpu$i: online=${cpu_online_stats["$i"]}"
                done
                rlRun "numactl -H"
                if [ "$origin_nr_cpus" = 1 ]; then
                        echo "Only 1 cpu available, can't offline.. skip"
                        rstrnt-report-result "nr_cpu_is_1" SKIP
                        rlPhaseEnd
                        exit 0
                fi
                # Test a cpu to determine if we can actually write to it.
                #
                # A handful of machines with this sys file don't allow writing to it,
                # causing the test to fail.
                if ! [[ -w /sys/devices/system/cpu/cpu1/online \
                    && -r /sys/devices/system/cpu/cpu1/online  ]] ; then
                        echo "/sys/devices/system/cpu/cpu1/online is not writeable, skipping"
                        rstrnt-report-result "cpu1_not_writeable" SKIP
                        exit 0
                fi
        rlPhaseEnd

        rlPhaseStartTest cpu_online_offline
                loop=5
                rlRun "dmesg -C"
                for i in $(seq 1 $loop); do
                        rlLog "Start cpu offline loop $i"
                        cpu_offline
                        sleep 1
                        rlLog "Start cpu online loop $i"
                        cpu_online
                        rlRun "dmesg | grep -E \"WARNING|Oops|BUG\"" 1-255
                done
        rlPhaseEnd

        if uname -r | grep -q ppc64le; then
                rlPhaseStartTest online_offline_ppc64le
                        rlRun "dmesg -C"
                        loop=5
                        for i in $(seq 1 $loop); do
                                rlRun "time ppc64_cpu --cores-on=1"
                                rlAssertEqauls "online cpus should be 1: expect 1==actual" "1" "$(nproc)"
                                rlRun "time ppc64_cpu --cores-on=all"
                                rlAssertEqauls "online cpus should be $origin_nr_cpus: expect $origin_nr_cpus==actual" "$origin_nr_cpus" "$(nproc)"
                                rlRun "dmesg | grep -E \"WARNING|Oops|BUG\"" 1-255
                        done
                rlPhaseEnd
        fi

        rlPhaseStartCleanup
                rlLogInfo "Restoring cpu online default to origin"
                for i in $(seq 1 $last_cpu); do
                        stat=${cpu_online_stats["$i"]}
                        rlLogInfo "cpu$i:online=$stat"
                        rlRun "echo $stat > /sys/devices/system/cpu/cpu$i/online"
                        rlAssertEquals "cpu oneline status restore: expect==actual" "$stat" "$(cat /sys/devices/system/cpu/cpu$i/online)"
                done
        rlPhaseEnd
rlJournalEnd
rlJournalPrintText

