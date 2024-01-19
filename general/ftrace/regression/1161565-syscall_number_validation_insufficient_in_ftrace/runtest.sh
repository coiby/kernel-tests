#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/ftrace/regression/1123102-kernel-panic-in-trace_find_cmdline/runtest.sh
#   Description: This is a regression test case for ftrace bug 1123102
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
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../include/runtest.sh || exit 1

BUG_INFO="1161565-syscall_number_validation_insufficient_in_ftrace"
SRC_FILE_F="ftrace.c"
SRC_FILE_P="perf.c"
BIN_FILE_F="ftrace_syscall"
BIN_FILE_P="perf_syscall"
IS_SUPPORTED=1

function test_clean(){
	rlPhaseStartTest  "Test $BUG_INFO"
		rlLogInfo "Run the ftrace syscall reproducer."

		rlRun "trace-cmd start -e syscalls:sys_enter_write"
		rlLogInfo "Run the ftrace reproducer for syscall"
		./$BIN_FILE_F &
		pid_ftrace=$!
		sleep 600
		kill

		rlLogInfo "Run the perf syscall reproducer."
		./$BIN_FILE_P &
		pid_perf=$!
		sleep 600
		rlLogInfo "Test pass, the kernel doesn't crash."
	rlPhaseEnd

	rlPhaseStartCleanup "Cleanup $BUG_INFO"
		rlRun "trace-cmd reset"
		kill $pid_ftrace
		kill $pid_perf
		true;
	rlPhaseEnd
}

rlJournalStart
	rlPhaseStartSetup "Setup $BUG_INFO"
		if [[ ! $(uname -m) =~ x86_64 ]];then
			rlLogWarning "Case is only For x86_64" && IS_SUPPORTED=0
		else
			if stat /run/ostree-booted > /dev/null 2>&1; then
				rpm -q gcc || rpm-ostree install -A --idempotent --allow-inactive gcc
				rpm -q trace-cmd || rpm-ostree install -A --idempotent --allow-inactive trace-cmd
			else
				rpm -q gcc || yum -y install gcc
				rpm -q trace-cmd || yum -y install trace-cmd
			fi
			rlRun "gcc $SRC_FILE_F -o $BIN_FILE_F"
			rlRun "gcc $SRC_FILE_P -o $BIN_FILE_P"
			mount |grep debug || rlRun "mount -t debugfs none /sys/kernel/debug"
		fi
	rlPhaseEnd
	((IS_SUPPORTED)) && test_clean

rlJournalEnd
rlJournalPrintText
