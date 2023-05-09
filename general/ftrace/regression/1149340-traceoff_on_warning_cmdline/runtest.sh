#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   1149340 - ftrace: add traceoff_on_warning kernel cmdline option
#   Description: This is a regression test case for ftrace bug 1123102
#   Author: Chunyu Hu <chuhu@redhat.com>
#   Update: Ziqian SUN <zsun@redhat.com>
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

BUG_INFO="1149340 - ftrace: add traceoff_on_warning kernel cmdline option"
SRC_FILE="ftrace-page-stress.c"
BIN_FILE="page-move-stress"
LOOP_TIMES=${LOOP:-10}

MOD=warn_mod/warn.ko
PROC_FILE=/proc/sys/kernel/traceoff_on_warning
TRACE_ON=/sys/kernel/debug/tracing/tracing_on
TRACE_BUFFER=/sys/kernel/debug/tracing/trace

REBOOT_TAG=/home/1149340_REBOOT
REBOOT_TAG_CLEAN=/home/1149340_REBOOT_2

TEST_DONE=/home/1149340_DONE
SET_BY_CMDLINE=${SET_BY_CMDLINE:-0}

IS_SUPPORTED=1

function kernel_param_setup(){
    if [ ! -f $REBOOT_TAG ];then
        grubby --args=traceoff_on_warning --update-kernel=$(grubby --default-kernel)
        touch $REBOOT_TAG
        rstrnt-reboot
    elif test -f $REBOOT_TAG_CLEAN;then
        rlLogInfo "Test finished."
        touch $TEST_DONE

        rlDie
    fi
    return 0;
}

function setup_phase(){
    rlPhaseStartSetup "Setup $BUG_INFO"
        mount |grep debug || rlRun "mount -t debugfs none /sys/kernel/debug"
        if [ ! -f $PROC_FILE ];then
            IS_SUPPORTED=0 && rlLogWarning "$PROC_FILE doesn't exit, so it's not supported for this parm"
            rlPhaseEnd
            return
        fi

        if test -f $REBOOT_TAG_CLEAN;then
            rlLogInfo "Test finished."
            touch $TEST_DONE
            rlPhaseEnd
        fi
        if test -f $TEST_DONE; then
            rlPhaseEnd
            return
        fi

        devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rpm -q trace-cmd || rpm-ostree install -A --idempotent --allow-inactive trace-cmd
            rpm -q ${devel_pkg} || rpm-ostree install -A --idempotent --allow-inactive ${devel_pkg}
        else
            rpm -q trace-cmd || yum -y install trace-cmd
            rpm -q ${devel_pkg} || yum -y install ${devel_pkg}
        fi

        pushd warn_mod
        [[ ! $(uname -m) =~ x86_64 ]] && unset ARCH
        make
        popd
        if [ ! -f $MOD ];then
            rlLogWarning "Compile the test mod fail."
            rlDie
        fi
    rlPhaseEnd
}

function test_phase(){
    [ ! $IS_SUPPORTED = 1 ] && return
    rlPhaseStartTest  "Test $BUG_INFO"
        if test -f $TEST_DONE; then
            rlPhaseEnd
            return
        fi
        if [ ! -f $PROC_FILE ];then
            IS_SUPPORTED=0 && rlLogWarning "$PROC_FILE doesn't exit, so it's not supported for this parm"
            rlPhaseEnd
            return
        fi
        kernel_param_setup
        if [ "$(cat /proc/sys/kernel/traceoff_on_warning)" = 0 ];then
            if [ "$(arch)" != "s390x" ]; then
                rlFail "Test if traceoff_on_warning take effect on kernel commandline"
            else
                rlLogWarning "Kernel commandline check for s390x do not work"
            fi
            rlRun " echo 1 > /proc/sys/kernel/traceoff_on_warning"
        elif [ "$(cat /proc/sys/kernel/traceoff_on_warning)" = 1 ] ; then
            rlPass "Test if traceoff_on_warning take effect on kernel commandline"
        fi

        rlRun "trace-cmd start -e sched:*" 0
        rlAssertGrep 1 "$TRACE_ON"
        rlAssertGrep 1 $TRACE_ON
        sleep 5;
        rlRun -l "insmod $MOD"
        # clean the warning dmesg.Don't let beaker catch the log.
        rlRun -l "dmesg |grep WARNING -A 15 && dmesg -C" 0-255
        sleep 5;
        rlRun -l "cat $TRACE_ON"
        rlRun -l "status=$(cat $TRACE_ON)" 0-254
        [ $? -ne 0 ] && rlLogWarning "What factor is it to cause the tracing_on is still showing on."
        sleep 5
        rlRun "> $TRACE_BUFFER" 0-254
        rlRun "> $TRACE_BUFFER" 0-254
        # No new record should be added to ring buffer.
        rlRun -l "lines=$(cat $TRACE_BUFFER |grep -v ^#| wc -l)"
        rlRun -l "cat $TRACE_BUFFER" 0-255
        rlAssert0 "Ringbuffer should contain 0 record." $lines
    rlPhaseEnd

    rlPhaseStartCleanup "Cleanup $BUG_INFO"
        if test -f $TEST_DONE; then
            rlPhaseEnd
            return
        fi

        trace-cmd reset
        rlRun -l "rmmod warn.ko" 0-255
        rlRun " echo 0 > /proc/sys/kernel/traceoff_on_warning"
        grubby --remove-args=traceoff_on_warning --update-kernel=$(grubby --default-kernel)
        rm $REBOOT_TAG
        touch $REBOOT_TAG_CLEAN
        rstrnt-reboot
    rlPhaseEnd
}


rlJournalStart
    setup_phase
    test_phase
rlJournalEnd
rlJournalPrintText
