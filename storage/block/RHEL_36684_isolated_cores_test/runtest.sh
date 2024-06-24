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
    rlRun "cat /proc/cmdline"
    cpu_num=$(cat /proc/cpuinfo  | grep processor | awk 'END{print}' | awk '{print$3}')
    cpu_left=$((cpu_num/2))
    cpu_right=$((cpu_left+2))

    rlRun "chmod a+x ${CDIR}/fio.sh"
    rlRun "taskset -c 1-${cpu_left} ${CDIR}/fio.sh"
    sleep 3
    rlRun "chcpu -d 1-${cpu_left},${cpu_right}-${cpu_num}"
    rlRun "chcpu -e 1-${cpu_left},${cpu_right}-${cpu_num}"
    rlRun "taskset -c 1-${cpu_left} ${CDIR}/fio.sh"
}

function k_param_setup()
{
    key_word="nohz_full"
    cmd_line=$(cat /proc/cmdline)
    if [[ ${cmd_line} == *"${key_word}"* ]];then
        rlLog "successfully add nohz_full into kernel parameter"
    else
        default_kernel=$(grubby --default-kernel)
        cpu_num=$(cat /proc/cpuinfo  | grep processor | awk 'END{print}' | awk '{print$3}')
        cpu_left=$((cpu_num/2))
        cpu_right=$((cpu_left+2))
        param="nohz_full=1-${cpu_left},${cpu_right}-${cpu_num}"
        grubby --args=${param} --update-kernel=${default_kernel}
        dracut -f
        rhts-reboot
    fi
}

function k_param_cleanup()
{
    key_word="nohz_full"
    cmd_line=$(cat /proc/cmdline)
    if [[ ${cmd_line} == *"${key_word}"* ]];then
        default_kernel=$(grubby --default-kernel)
        cpu_num=$(cat /proc/cpuinfo  | grep processor | awk 'END{print}' | awk '{print$3}')
        cpu_left=$((cpu_num/2))
        cpu_right=$((cpu_left+2))
        param="nohz_full=1-${cpu_left},${cpu_right}-${cpu_num}"
        grubby --remove-args=${param} --update-kernel=${default_kernel}
        dracut -f
        rhts-reboot
    else
        rlRun "cat /proc/cmdline"
        rlLog "successfully removed nohz_full kernel parameter"
    fi
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        if [[ -e "${CDIR}/test_done_flage" ]];then
            k_param_cleanup
        else
            k_param_setup
            run_test
            touch "${CDIR}"/test_done_flage
            k_param_cleanup
        fi
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
