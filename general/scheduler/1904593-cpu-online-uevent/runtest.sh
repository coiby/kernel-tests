# /bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/1904593-cpu-online-uevent
#   Description: bz1904593 regression test
#   Author: Waylon Cude <wcude@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc.
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

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

origin_nr_cpus=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)

rlJournalStart
    rlPhaseStartTest
        if [ "$origin_nr_cpus" = 1 ]; then
            echo "Only 1 cpu available, can't offline.. skip"
            report_result "nr_cpu_is_1" SKIP
            # rlPhaseEnd
            exit 0
        fi

        if ! [[ -w /sys/devices/system/cpu/cpu1/online \
            && -r /sys/devices/system/cpu/cpu1/online  ]] ; then
            echo "/sys/devices/system/cpu/cpu1/online is not writeable, skipping"
            report_result "cpu1_not_writeable" SKIP
            exit 0
        fi

        gcc -o repro repro.c -ludev

        rlRun ./repro
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText

