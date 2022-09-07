#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/ftrace/regression/602804-panic-while-using-userstacktrace
#   Description: Bug 602804 - Panic while using userstacktrace
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
        rlRun "Initialize"
    rlPhaseEnd

    rlPhaseStartTest
    if [ ! -e ${T_PATH_TRACE_EVENTS}/exceptions/page_fault_kernel/enable ] || ! grep --quiet CONFIG_STACK_TRACER=y /boot/config-`uname -r` ; then
        rlLogInfo "Stack Tracer is not configured in this kernel, or page fault kernel exceptions is not traceable. Skip the test"
        report_result $TEST SKIP 0
    else
        rlAssertGrep "CONFIG_STACK_TRACER=y" /boot/config-`uname -r` || rlDie
        rlRun "echo 1 > ${T_PATH_STACK_TRACE}" 0                     || rlDie
        rlRun "echo userstacktrace > ${T_PATH_TRACE_OPTIONS}" 0
        rlAssertGrep "^userstacktrace" ${T_PATH_TRACE_OPTIONS}
        KXY=$(uname -r | awk -F '.' '{print $1"."$2}')
        VCOMPARE=$(echo "${KXY}>=3" | bc)
        if [ ${VCOMPARE} -eq 1 ]; then
            rlRun "echo 1 > ${T_PATH_TRACE_EVENTS}/exceptions/page_fault_kernel/enable" 0
        else
            rlRun "echo 1 > ${T_PATH_TRACE_EVENTS}/kmem/mm_kernel_pagefault/enable" 0
        fi
        rlWatchdog "find / >/dev/null 2>&1" 10
        rlLog "Still alive"
    fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "Teardown"
    rlPhaseEnd
rlJournalEnd
