#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   1179759 - ftrace: out of tree trace event not working since the taint check.
#   Description: This is a regression test case for ftrace bug 1179759
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
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
. ../../../../cki_lib/libcki.sh || exit 1
. ../../../../kernel-include/runtest.sh || exit 1

BUG_INFO="1179759 - Trace event on out of tree module not functional"
SRC_FILE="ftrace-page-stress.c"
BIN_FILE="page-move-stress"
LOOP_TIMES=${LOOP:-10}

MOD=event_mod/pita.ko
PROC_FILE=/proc/sys/kernel/traceoff_on_warning
TRACE_ON=/sys/kernel/debug/tracing/tracing_on
TRACE_BUFFER=/sys/kernel/debug/tracing/trace

function setup_phase(){
    rlPhaseStartSetup "Setup $BUG_INFO"
        mount |grep debug || rlRun "mount -t debugfs none /sys/kernel/debug"
        devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rpm -q trace-cmd || rpm-ostree install -A --idempotent --allow-inactive trace-cmd
            rpm -q ${devel_pkg} || rpm-ostree install -A --idempotent --allow-inactive ${devel_pkg}
        else
            rpm -q trace-cmd || yum -y install trace-cmd
            rpm -q ${devel_pkg} || yum -y install ${devel_pkg}
        fi
        [[ ! $(uname -m) =~ x86_64|i386 ]] && unset ARCH
        pushd event_mod
        make
        popd
        if [ ! -f $MOD ];then
            rlLogWarning "Compile the test mod fail."
            rlDie
        fi
    rlPhaseEnd
}

function test_phase(){
    rlPhaseStartTest  "Test $BUG_INFO"
        rlRun -l "insmod $MOD"
        rlRun "trace-cmd start -e pita:*" 0
        # On rhel6, the taint file is not supported
        [ -f "/sys/module/pita/taint" ] && rlRun -l "cat /sys/module/pita/taint"
        rlRun -l "echo 1 >/sys/kernel/debug/pita/test"
        [ -f "/sys/module/pita/taint" ] && rlAssertGrep "OE" /sys/module/pita/taint
        rlRun -l "cat $TRACE_BUFFER | tail -n 20"
        rlRun -l "cat $TRACE_BUFFER | tee trace.txt"
        rlAssertGrep "pita" trace.txt
    rlPhaseEnd

    rlPhaseStartCleanup "Cleanup $BUG_INFO"
        trace-cmd stop
        rlRun -l "rmmod pita.ko" 0-255
        true;
    rlPhaseEnd
}

rlJournalStart
    setup_phase
    test_phase
rlJournalEnd
rlJournalPrintText
