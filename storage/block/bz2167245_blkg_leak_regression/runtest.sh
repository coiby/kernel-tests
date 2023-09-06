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
    if rlIsRHEL 8; then
        run4rhel8
    elif rlIsRHEL '>=9.0'; then
        run4rhel9
    else
        rlLog "skip this case"
        return 0
    fi
    rlRun "rm -rf trace.log"
}

function run4rhel8()
{
    rlRun "chmod a+x rhel8_blkg.bt"
    rlRun "./rhel8_blkg.bt"
    rlRun "./rhel8_blkg.bt | tee trace.log"
    rlRun "cat trace.log |  grep 'blkg_alloc'"
    a=$(cat trace.log |  grep 'blkg_alloc' | head -n 1 |  awk -F 'blkg_alloc' '{print $2}')
    rlRun "cat trace.log | grep \"${a}\""
    b=$(cat trace.log | grep "${a}" | wc -l)
    if [ ${b} == 2 ];then
        rlPass "Testing Pass"
    else
        rlFail "Testing Failed,request queue won't be freed"
    fi
}

function run4rhel9()
{
    rlRun "chmod a+x blkg.bt"
    rlRun "./blkg.bt"
    rlRun "./blkg.bt | tee trace.log"
    rlRun "cat trace.log |  grep 'blk_mq_release'"
    a=$(cat trace.log |  grep 'blk_mq_release' | head -n 1 |  awk -F 'blk_mq_release' '{print $2}')
    rlRun "cat trace.log | grep \"${a}\""
    b=$(cat trace.log | grep "${a}" | wc -l)
    if [ ${b} == 2 ];then
        rlPass "Testing Pass"
    else
        rlFail "Testing Failed,request queue won't be freed"
    fi
}

function check_log()
{
    rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
    rlRun "dmesg | grep 'BUG:'" 1 "check the errors"
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
