#! /bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/nl_process_stats
#   Description: This is a tests for netlink task stats interface
#   Author: Chunyu Hu <chuhu@redhat.com>
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

. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../include/runtest.sh

trap 'Cleanup' SIGHUP SIGINT SIGQUIT SIGTERM SIGUSR1

function Cleanup()
{
	rm getdelays -f
}

skip=0

rlJournalStart
	rlPhaseStartSetup
		rlRun "yum -y install kernel-headers"
		rlRun "gcc getdelays.c -o getdelays" || skip=1
	rlPhaseEnd
	if ((skip)); then
		rlPhaseStartTest "Skip-test"
		rlLog "Skipped as compile failure"
		rlPhaseEnd
	else
		rlPhaseStartTest
			rlRun "./getdelays -p $$ -d -q -i" -l
			rlRun "./getdelays -C /sys/fs/cgroup/memory -d -q -i" -l
			rlRun "./getdelays -C /sys/fs/cgroup/cpu,cpuacct -d -q" -l
			rlRun "./getdelays -C /sys/fs/cgroup/pid -d" -l
			rlLogInfo "taskset -c 1 sleep 2 &"
			taskset -c 1 sleep 2 &
			rlRun "./getdelays -m 1 -d" -l
		rlPhaseEnd
	fi

	rlPhaseStartCleanup
		Cleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

