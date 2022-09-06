#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/ftrace/regression/601047-deadlock
#   Description: Bug 601047 - Deadlock while using stack tracer(ftrace)
#   Author: Caspar Zhang <czhang@redhat.com>
#   Update: Ziqian SUN <zsun@redhat.com>
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

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../include/runtest.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
         rlRun "Initialize 'Teardown'"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun -l "grep CONFIG_STACK_TRACER=y /boot/config-`uname -r`" 0-254
    if [ $? -ne 0 ];then
        rlLogInfo "Stack Tracer is not configured in This kernel.Skip the test"
    else
        rlRun "echo 1 > ${T_PATH_STACK_TRACE}" 0                     || rlDie
        rlRun "echo 1 > ${T_PATH_TRACE_STACK_MAXSZ}" 0               || rlDie
        rlLogInfo "repeat writing to ${T_PATH_TRACE_STACK_MAXSZ}"
        while :; do
            echo 1 > ${T_PATH_TRACE_STACK_MAXSZ} >/dev/null 2>&1;
        done &
        pid1=$!
        rlLogInfo "repeat reading from ${T_PATH_TRACE_STACK}"
        while :; do
            cat ${T_PATH_TRACE_STACK} >/dev/null 2>&1;
        done &
        pid2=$!
        rlRun "sleep 1200"
        rlLog "Still alive"
    fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "kill -9 $pid1 $pid2" 0-254
        rlRun "Teardown"
    rlPhaseEnd
rlJournalEnd
