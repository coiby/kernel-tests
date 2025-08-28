#!/bin/bash
# shellcheck disable=SC1090
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/sched_cfs_rq_starve
#   Description: cpu cgroup low quota cna starve cfs runqueue and tasks.
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
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

# Enable TMT testing for RHIVOS
. ../../../cki_lib/libcki.sh || exit 1

. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../include/runtest.sh || exit 1

rlJournalStart
	rlPhaseStartSetup
		np=$(nproc)
		rlLog "Found $np CPUs"
		if ((np < 8)); then
			rlLog "Skipping test: Insufficient CPUs (need at least 8, found $np)"

			# RHEL continues to use SKIP to avoid cluttering the data warehouse with WARN results.
			# For RHIVOS, use rlFail in Setup phase to leave a WARN result for FuSa validator requirements.
			if ! cki_is_kernel_automotive; then
				rstrnt-report-result sched_cfs_rq_starve SKIP
			else
				rlFail "Insufficient CPUs"
			fi

			rlPhaseEnd
			rlJournalEnd
			rlJournalPrintText
			exit 0
		fi

		check_cgroup_version
		cgroup_create hello cpu
		cgroup_path=$(cgroup_get_path hello cpu)
		if [ "$CGROUP_VERSION" = 1 ]; then
			rlRun "echo 1000 > $cgroup_path/cpu.cfs_quota_us"
		else
			rlRun "echo 1000 > $cgroup_path/cpu.max"
		fi
		rlRun "gcc cputest.c -o cputest"
	rlPhaseEnd

	rlPhaseStartTest
		loop=0
		sec=120

		rlRun "./do_it.sh"
		rlLog "sleeping 30 seconds to wait for processes ready"
		sleep 30
		rlLog "sample tasks executing time(pid,sum_runtime)"
		for _ in $(seq 1 5); do
			./show.sh > old
			rlRun -l "cat old" 0 "old: looping $loop"
			rlLog "sleeping 120 seconds ..."
			sleep $sec
			./show.sh > new
			rlRun -l "cat new" 0 "new: looping $loop"
			# If got starve, it should be failed.
			if rlRun "./compare.sh | grep starve" 1-255 "check if any cputests starve for $sec seconds"; then
				rlFileSubmit old
				rlFileSubmit new
				break
			fi
			((loop++))
		done
	rlPhaseEnd

	rlPhaseStartCleanup
		rlRun "pkill -9 cputest" 0-255
		rlRun "cgroup_destroy hello cpu" 0-255
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
