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

. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1
. ../../../general/include/libmem.sh || exit 1

# Function to set up cgroup with cpuset controller
# Parameters:
#   $1 - cpus: CPUs to be allowed in cpuset
#   $2 - mems: Memory nodes to be allowed in cpuset
function setup_cgroup_cpuset()
{
	local cpus=$1
	local mems=$2

	# Create a new cgroup with cpuset controller
	cgroup_create "sched_setaffinity" "cpuset"

	# Set the memory nodes for the cpuset
	if ! cgroup_set_file "sched_setaffinity" "cpuset" "cpuset.mems=$mems"; then
		rlReport "cpuset setup" FAIL
		exit 1
	else
		rlLog "cpuset.mems=0"
	fi

	# Set the CPUs for the cpuset
	if ! cgroup_set_file "sched_setaffinity" "cpuset" "cpuset.cpus=$cpus"; then
		rlReport "cpuset setup" FAIL
		exit 1
	else
		# Log the current cpuset CPUs configuration
		cgroup_get_file sched_setaffinity cpuset cpuset.cpus
		rlLog "cpuset.cpus=0"
	fi

	# Compile the test program
	if ! rlRun "gcc sched_setaffinity.c -o sched_setaffinity"; then
		exit 1
	fi
}

# Start the test journal
rlJournalStart

	rlPhaseStartSetup
		# Show the running kernel version
		rlShowRunningKernel

		# Get the number of CPUs available in the system
		nr_cpu=$(grep -wc processor /proc/cpuinfo)

		# If less than 2 CPUs, skip the test
		if ((nr_cpu < 2)); then
			rstrnt-report-result "not enough processor" SKIP
			exit 0
		fi

		# Setup the cpuset with default configuration (cpus=0, mems=0)
		setup_cgroup_cpuset 0 0
	rlPhaseEnd

	# Test 1 - Zero cpumask (testing invalid cpumask)
	rlPhaseStartTest "zero cpumask"
		# Get the original allowed CPU mask from the /proc/self/status
		original_mask="$(awk -F' ' '/Cpus_allowed_list/ {print $2}' /proc/self/status)"

		# Run the sched_setaffinity syscall with an invalid cpumask (cpus=0)
		# Expect failure due to an invalid cpumask
		rlRun -l "./sched_setaffinity -1 -1 22 $original_mask" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd

	# Test 2 - Beyond cpuset limitation (testing cpumask beyond the cpuset limit)
	rlPhaseStartTest "beyond cpuset limitation"
		# Run the sched_setaffinity syscall with cpumask set to an invalid CPU outside of the cpuset
		# Expect failure due to cpus beyond the cpuset boundaries, cpumask should remain unchanged
		rlRun -l "cgexec.sh sched_setaffinity cpuset ./sched_setaffinity 1 -1 22 0" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd

	# Test 3 - Intersect cpuset limitation (testing partial overlap between cpumask and cpuset)
	rlPhaseStartTest "intersect cpuset limitation"
		# Run the sched_setaffinity syscall with a cpumask that partially intersects with cpuset (cpus 0-1)
		# Expect success, with the cpumask being the intersection of cpuset CPUs and the specified cpumask
		rlRun -l "cgexec.sh sched_setaffinity cpuset ./sched_setaffinity 0-1 0 0 0" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd

	# Test 4 - Within cpuset limitation (testing cpumask within cpuset limit)
	rlPhaseStartTest "within cpuset limitation"
		# Destroy the previous cpuset configuration and create a new one that limits cpus to 0-1
		cgroup_destroy "sched_setaffinity" "cpuset"
		setup_cgroup_cpuset 0-1 0

		# Run the sched_setaffinity syscall with cpumask that is a subset of the cpuset (cpus=1)
		# Expect success, with cpumask being the intersection of cpuset CPUs and the specified cpumask
		rlRun -l "cgexec.sh sched_setaffinity cpuset ./sched_setaffinity 1 0 0 1" 0 "cpuset_cpu, retval, errno, cpumask"
	rlPhaseEnd

	rlPhaseStartCleanup
		# Destroy the cpuset cgroup and remove the compiled test binary
		cgroup_destroy "sched_setaffinity" "cpuset"
		rm -f sched_setaffinity
	rlPhaseEnd

# End the test journal
rlJournalEnd

# Print the journal text output to the console
rlJournalPrintText
