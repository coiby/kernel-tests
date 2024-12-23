#! /bin/bash
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

. /usr/share/beakerlib/beakerlib.sh || exit 1

if [ -z "$OUTPUTFILE" ]; then
	export OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`
fi

origin_nr_cpus=$(grep -c -w ^processor /proc/cpuinfo)

rlJournalStart
    rlPhaseStartTest
        if rlIsRHEL '8.4'; then
            echo "Known failure on RHEL 8.4 .. skip"
            rstrnt-report-result "invalid_rhel_version" SKIP
            exit 0
        fi

        if [ "$origin_nr_cpus" = 1 ]; then
            echo "Only 1 cpu available, can't offline.. skip"
            rstrnt-report-result "nr_cpu_is_1" SKIP
            # rlPhaseEnd
            exit 0
        fi

        if ! [[ -w /sys/devices/system/cpu/cpu1/online \
            && -r /sys/devices/system/cpu/cpu1/online  ]] ; then
            echo "/sys/devices/system/cpu/cpu1/online is not writeable, skipping"
            rstrnt-report-result "cpu1_not_writeable" SKIP
            exit 0
        fi

        gcc -o repro repro.c -ludev

        rlRun ./repro
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText

