#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   general/scheduler/sched_setaffinity
#   Description: sched_setaffinity test with cpuset controller
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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

TEST="/kernel-tests/general/scheduler/sched_setaffinity"

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../../kernel-include/runtest.sh || exit 1
. ../../../general/include/libmem.sh

function setup_cgroup_cpuset()
{
	local cpus=$1
	local mems=$2
	cgroup_create "sched_setaffinity" "cpuset"
	if ! cgroup_set_file "sched_setaffinity" "cpuset" "cpuset.mems=$mems"; then
		rlReport "cpuset setup" FAIL
		exit 1
	else
		rlLog "cpuset.mems=0"
	fi
	if ! cgroup_set_file "sched_setaffinity" "cpuset" "cpuset.cpus=$cpus"; then
		rlReport "cpuset setup" FAIL
		exit 1
	else
		cgroup_get_file sched_setaffinity cpuset cpuset.cpus
		rlLog "cpuset.cpus=0"
	fi
	if ! rlRun "gcc sched_setaffinity.c -o sched_setaffinity"; then
		exit 1
	fi
}

rlJournalStart
	rlPhaseStartSetup
		rlShowRunningKernel
		nr_cpu=$(grep -wc processor /proc/cpuinfo)
		if ((nr_cpu < 2)); then
			rstrnt-report-result "not enough processor" SKIP
			exit 0
		fi
		setup_cgroup_cpuset 0 0
	rlPhaseEnd

	rlPhaseStartTest "zero cpumask"
		original_mask="$(awk -F' ' '/Cpus_allowed_list/ {print $2}' /proc/self/status)"
		rlRun -l "./sched_setaffinity -1 -1 22 $original_mask" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd

	rlPhaseStartTest "beyond cpuset limitation"
		rlRun -l "cgexec.sh sched_setaffinity cpuset ./sched_setaffinity 1 -1 22 0" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd


	rlPhaseStartTest "intersect cpuset limitation"
		rlRun -l "cgexec.sh sched_setaffinity cpuset ./sched_setaffinity 0-1 0 0 0" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd

	rlPhaseStartTest "within cpuset limitation"
		cgroup_destroy "sched_setaffinity" "cpuset"
		setup_cgroup_cpuset 0-1 0
		rlRun -l "cgexec.sh sched_setaffinity cpuset ./sched_setaffinity 1 0 0 1" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd

	rlPhaseStartCleanup
		cgroup_destroy "sched_setaffinity" "cpuset"
		rm -f sched_setaffinity
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
