#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/vm/hugepage/cmdline
#   Description: hugepages from cmdline
#   Author: Caspar Zhang <czhang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
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

# Include environment
# shellcheck disable=SC1091
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Testcase #1:
#   hugepages= option (for all)
# Testcaes #2:
#   hugepagesz= option (for RHEL6|7 x86_64, ia64, ppc64)

MEMINFO=/proc/meminfo
PROCFS_PATH=/proc/sys/vm
SYSFS_PATH=/sys/kernel/mm/hugepages

function SetupTest()
{
    if ! grep -q hugetlbfs /proc/filesystems; then
        # Bug 1143877 - hugetlbfs: disabling because there are no supported hugepage sizes
        rlLog "hugetlbfs not found in /proc/filesystems, skipping test"
        rstrnt_report_result Test_Skipped PASS 99
        rlPhaseEnd
        rlJournalEnd
        rlJournalPrintText
        exit 0
    fi
    export HP_NR=0
    export MULTI_HP=NO
    export CMDLINEARGS=""

    rlRun "hpsz=$(awk '/Hugepagesize/ { print $2}' /proc/meminfo)"
    # HP_SIZE for ia64 is too big (256M)
    rlRun "test $(arch) = ia64 && HP_NR=20 || HP_NR=50"
    # HP_SIZE for aarch64 is too big (512M or 2M)
    # shellcheck disable=SC2154
    rlRun "test $(arch) = aarch64 && test ${hpsz} = 524288 && HP_NR=2" 0-1

    CMDLINEARGS="hugepages=${HP_NR}"
    if [ "$(arch)" = "x86_64" ] || [ "$(arch)" = "ppc64" ] || [ "$(arch)" = "aarch64" ]; then
        if (grep -E -q '(release 6|release 7|release 8|release 9)' /etc/redhat-release) &&
            (grep -q 'pdpe1gb' /proc/cpuinfo); then
            MULTI_HP=YES
            CMDLINEARGS="hugepages=${HP_NR} hugepagesz=1G hugepages=1"
        fi
    fi
    # Set CMDLINE
    rlLog "Passing ${CMDLINEARGS}"
    env CMDLINEARGS="${CMDLINEARGS}" bash ../../../cmdline_helper/runtest.sh || exit 1
}

function StartTest()
{

    # Start Test
    export RESULT="PASS"
    export TEST=hugepage-cmdline

    # From /proc/meminfo
    rllog " + check results from ${MEMINFO}"
    rlRun "hp_total=$(awk '/HugePages_Total/ {print $2}' ${MEMINFO})"
    # shellcheck disable=SC2154
    rllog " |- HugePages_Total = $hp_total"
    rlRun "hp_free=$(awk '/HugePages_Free/ {print $2}' ${MEMINFO})"
    # shellcheck disable=SC2154
    rlLog " |- HugePages_Free = ${hp_free}"
    if [ "x$hp_total" != "x${HP_NR}" ] || [ "x$hp_free" != "x${HP_NR}" ]; then
        rlLog " \`- check ${MEMINFO} failed"
        RESULT=FAIL
    else
        rlLog " \`- check /proc/meminfo passed"
    fi

    # From procfs
    rlLog " + check results from ${PROCFS_PATH}"
    rlRun "hp_total=$(cat ${PROCFS_PATH}/nr_hugepages)"
    rlLog " |- nr_hugepages = $hp_total"
    if [ "x$hp_total" != "x${HP_NR}" ]; then
        rlLog " \`- check ${PROCFS_PATH} failed"
        RESULT=FAIL
    else
        rlLog " \`- check ${PROCFS_PATH} passed"
    fi

    # From sysfs
    if grep -E -q '(release 6|release 7|release 8)' /etc/redhat-release; then
        rlRun "HP_SIZE=$(awk '/Hugepagesize/ {print $2}' ${MEMINFO})"
        rllog " + check results from ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/"
        rlRun "hp_total=$(cat ${SYSFS_PATH}/hugepages-"${HP_SIZE}"kB/nr_hugepages)"
        rllog " |- nr_hugepages = $hp_total"
        rlRun "hp_free=$(cat ${SYSFS_PATH}/hugepages-"${HP_SIZE}"kB/free_hugepages)"
        rllog " |- free_hugepages = $hp_free"
        if [ "x$hp_total" != "x${HP_NR}" ] || [ "x$hp_free" != "x${HP_NR}" ]; then
            rlLog " \`- check ${SYSFS_PATH} failed"
            RESULT=FAIL
        else
            rlLog " \`- check ${SYSFS_PATH} passed"
        fi

        if [ "${MULTI_HP}" = "YES" ]; then
            result_appendix="-1G"
            HP_SIZE=1048576 # 1GB
            rlLog " + check results from ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/"
            rlRun "hp_total=$(cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/nr_hugepages)"
            rllog " |- nr_hugepages = $hp_total"
            rlRun "hp_free=$(cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/free_hugepages)"
            rllog " |- free_hugepages = $hp_free"
            if [ "x$hp_total" != "x1" ] || [ "x$hp_free" != "x1" ]; then
                rlLog " \`- check ${SYSFS_PATH} failed"
                RESULT=FAIL
            else
                rlLog " \`- check ${SYSFS_PATH} passed"
            fi
        fi
    fi

    if [ "${RESULT}" = "PASS" ]
    then
        report_result "${TEST}${result_appendix}" ${RESULT}
    else
        report_result "${TEST}${result_appendix}" ${RESULT} 1
    fi
    export RSTRNT_REBOOTCOUNT=0
}

function CleanupTest()
{
    if [ -f cmdline_file ]; then
        CMDLINEARGS=$(cat cmdline_file)
    else
        rlRun "touch cmdline_file"
        rlRun "echo ${CMDLINEARGS} > cmdline_file"
    fi
    rlLog "Passing -${CMDLINEARGS}"
    env CMDLINEARGS="-${CMDLINEARGS}" bash ../../../cmdline_helper/runtest.sh || exit 1
}
if [ -f iter_file ]; then
    iteration=$(cat iter_file)
else
    touch iter_file
    echo 0 > iter_file
    iteration=0
fi
rlJournalStart
    if ((iteration++ < 2)); then
        # shellcheck disable=SC2086
        echo ${iteration} >  iter_file
        rlPhaseStartSetup
            rlShowRunningKernel
            rlRun "SetupTest"
        rlPhaseEnd
        rlPhaseStartTest
            rlRun "StartTest"
        rlPhaseEnd
    fi
    rlPhaseStartCleanup
        rlRun "CleanupTest"
        rlRun "rm iter_file cmdline_file"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
