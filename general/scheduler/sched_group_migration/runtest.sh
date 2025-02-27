#!/bin/bash
# shellcheck disable=SC1090
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/sched_group_migration_test
#   Description: This is a tests for scheduler group migration tests
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
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

# run time for each sub test in tests/type/bug
RUN_TIME=${RUN_TIME:-120}

# For cleanup, for sub test cases filling in
KILL_PIDS=""
KILL_NAMES=""

function test_setup()
{
	dump_cgroup_info $$
}

function test_clean()
{
	true
}

# Run all subtests in tests folder, in type-bugid pattern
# such as 'ldb_policy-bz1722234'
function run_sub_tests()
{
	local sub_dirs  # case type / scenario
	local sub_dirs2 # bug id or regression type
	local t
	local reg
	local pwd=$(pwd)

	sub_dirs=$(find tests -mindepth 1 -maxdepth 1 -type d -printf "%P\n")
	rlLogInfo "Sub tests: $sub_dirs"
	cd tests
	for t in $sub_dirs; do
		pushd $t
		sub_dirs2=$(find . -mindepth 1 -maxdepth 1 -type d -printf "%P\n")
		# bug number or sub type
		for reg in ${sub_dirs2}; do
			pushd $reg
			rlPhaseStartTest ${t}-${reg}
				source ${reg}.sh
				rlRun "$reg ${reg}-test"
				rlLog "Sleeping for ${RUN_TIME}s"
				sleep $RUN_TIME
				rlRun "${reg}_cleanup"
				for p in ${KILL_NAMES}; do
					pkill -f $p
				done
				for p in ${KILL_PIDS}; do
					kill $p
				done
			rlPhaseEnd
			popd
		done
		popd
	done
	cd $pwd
	return
}

rlJournalStart
	rlPhaseStartSetup
		test_setup
	rlPhaseEnd

	run_sub_tests

	rlPhaseStartCleanup
		test_clean
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

