#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/sched_eevdf
#   Description: tests for eevdf schedule related
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

. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../include/runtest.sh

function check_support_eevdf()
{
	local major=$(uname -r | cut -d. -f 1)
	local minor=$(uname -r | cut -d. -f 2)

	# the syscall is added since 6.12
	if ((major > 6)) || ((major == 6 && minor >=12)); then
		return 0
	fi
	return 1
}

function run_tests()
{
	local testcase
	local func
	local dir
	while read testcase; do
		[[ ${testcase} =~ ^# ]] && continue
		func=$(basename $testcase | awk -F. '{print $1}')
		dir=$(dirname $testcase)
		echo running $testcase
		# shellcheck disable=SC1090
		source $testcase || rlDie "no $testcase"
		pushd $dir
		rlPhaseStartTest $func
		$func
		rlPhaseEnd
		popd
	done < caselist
}

rlJournalStart
	rlPhaseStartSetup
		rlRun "cat caselist" -l
		rlRun "sh ../../include/scripts/wget-kernel.sh --running --header -i"
	rlPhaseEnd

	if ! check_support_eevdf; then
		rlReport "eevdf not support SKIP" PASS
		exit 0
	fi

	run_tests

	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

