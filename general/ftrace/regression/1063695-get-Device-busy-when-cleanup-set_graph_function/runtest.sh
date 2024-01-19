#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of bz1063695
#   Description: autotest for bz1063695
#   Author: Yahuan Cong <ycong@redhat.com>
#   Update: Ziqian SUN <zsun@redhat.com>
#
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../include/runtest.sh || . /mnt/tests/kernel/general/ftrace/include/runtest.sh || exit 1

set -o pipefail

result=PASS

function bz_test()
{
    mount -t debugfs none /sys/kernel/debug
    rlAssertMount /sys/kernel/debug
    [ $? -ne 0 ] && rlDie

    CheckTracingSupport tracer function_graph ||
    SkipTracingTest filter set_graph_function

    cd /sys/kernel/debug/tracing

    for _ in $(seq 3); do
        rlRun "cat current_tracer"
        rlRun "echo '*open*' > set_graph_function"
        rlRun "origin=$(cat set_graph_function | wc -l)" 0-255

        rlRun "echo '!*cgroup*' >> set_graph_function"
        rlAssertNotGrep cgroup set_graph_function
        [ ! $? = 0 ] && result=FAIL
        rlRun "remain=$(cat set_graph_function | wc -l)" 0-255

        rlRun "echo '!*open*' >> set_graph_function"
        [ ! $? = 0 ] && result=FAIL
        rlAssertNotGrep irq set_graph_function
    done
}

# ----------Test Start------------
rlJournalStart
    rlPhaseStartTest
        rlRun "bz_test"
    rlPhaseEnd

    rstrnt-report-result $TEST $result
    rstrnt-report-log -l ${of}

    rlPhaseStartCleanup
        echo nop > /sys/kernel/debug/tracing/current_tracer
        echo > /sys/kernel/debug/tracing/set_graph_function
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
