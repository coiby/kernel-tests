#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/ftrace/regression/1033299-ftrace-WARNING-kernel_trace_ftrace/runtest.sh
#   Description: This is a regression test case for ftrace bug  1033299
#   Author: Yanzhen Ren <yren@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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

function bz_test()
{
    rlPhaseStartTest
        rlRun "dmesg|grep 'WARNING:\ at\ kernel/trace/ftrace.c'" 1-255
    rlPhaseEnd
}

rlJournalStart
    rlPhaseStartSetup
        rlRun "MountDebugfs"
        rlCheckMount ${T_PATH_SYS_DEBUG} || rlDie

        rlRun "CheckTracingSupport tracer function_graph" 0-255 ||
        rlRun "SkipTracingTest tracer function_graph" 0-255

        rlRun "EnableTracer function_graph" || rlDie
        rlRun "grep -w function_graph ${T_PATH_CURR_TRACER}"
        rlRun "modprobe nfsd" || rlDie
        rlRun "EnableTracer nop"
        rlRun "grep -w nop ${T_PATH_CURR_TRACER}"
    rlPhaseEnd

    bz_test

    rlPhaseStartCleanup
        rlRun "UmountDebugfs"
    rlPhaseEnd
rlJournalEnd
