#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/ftrace/regression/1033299-ftrace-WARNING-kernel_trace_ftrace/runtest.sh
#   Description: This is a regression test case for ftrace bug  1260517
#   Author: Ziqian SUN <zsun@redhat.com>
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
. ../../include/runtest.sh || . /mnt/tests/kernel/general/ftrace/include/runtest.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlRun "MountDebugfs"
        rlCheckMount ${T_PATH_SYS_DEBUG} || rlDie
    rlPhaseEnd

    rlPhaseStartTest "Test if pids visible to user"
        rlRun "CheckTracingSupport tracer function_graph" 0-255 ||
        rlRun "SkipTracingTest tracer function_graph" 0-255
        rlRun "EnableTracer function_graph" || rlDie
        rlRun "grep -w function_graph ${T_PATH_CURR_TRACER}"
        rlRun -l "ps aux"
        rlAssertGreater "Should be more than two lines" $(ps aux | wc -l) 2
    rlPhaseEnd

    rlPhaseStartCleanup
       echo 'nop' > ${T_PATH_CURR_TRACER} 
    rlPhaseEnd
rlJournalEnd
