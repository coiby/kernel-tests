#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of kunit
#   Description: KUNIT: a Kernel Unit Testing Framework
#   Author: Nico Pache <npache@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

#processes a test result from the debug/sysfs
process_results(){
	TMPFILE=$(mktemp) || exit 1
	OUTFILE=$(mktemp) || exit 1
	rlLog "processing results from test ${1}"
	sed -i 's/KTAP version 1//g' "$1" #remove KTAP VERSION
	sed -i '/^$/d' "$1" #remove all empty lines
	sed -i 's/    //g' "$1" #remove all tab
	sed -i '/^#/d' "$1" #remove comments
	sed -i 's/#.*//' "$1" #remove comments
	sed -i '$d' "$1" #remove last line.
	sed -i '/^\(ok\|not ok\)/!d' "$1" #removeall but 1..N and ok/not ok
	uniq "$1" > "$TMPFILE"  #remove dup

	lines=$(wc -l "$TMPFILE")
	echo "1..$lines" | cat - "$TMPFILE" > $OUTFILE
	tappy "$OUTFILE" &> "$TMPFILE"
	RESULT_OUTPUT=$(cat "$TMPFILE" |tail -1)
	if [ "$RESULT_OUTPUT" = "OK" ]; then
		return 0
	else
		return 1
	fi
}

#Include Beaker environment
. ../cki_lib/libcki.sh || exit 1
. ../kernel-include/runtest.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# variables used by beakerlib
TEST="KUNIT"
export PACKAGE="kernel"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Global parameters
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# load kunit module names into a array
readarray -t test_arr < kunit-tests.list

rlJournalStart
#-------------------- Setup ---------------------
	rlPhaseStartSetup
		#install tappy
		pip3 install tap.py
		if [ $? -ne 0 ]; then
			rlLog "Pip unable to install tap.py, aborting test"
			rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
			exit 1
		fi

		# kunit module was added on kernel 4.18.0-279 (BZ#1900119)
		if cki_kver_lt "4.18.0-279"; then
			# kernel is too old to support kunit module
			rstrnt-report-result $TEST SKIP
			rlPhaseEnd
			rlJournalEnd
			#print the test report
			rlJournalPrintText
			exit 0
		fi

		module_pkg=$(K_GetRunningKernelRpmSubPackageNVR modules-internal)

		if ! rpm -q $module_pkg; then
			echo "FAIL: ${module_pkg} is not installed, aborting test"
			rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
			exit 1
		fi
		#test for kunit
		rlRun "modprobe kunit"
		if [ $? -ne 0 ]; then
			rlFail "Could not load KUNIT module, aborting test"
			rstrnt-report-result $TEST FAIL
			rlPhaseEnd
			rlJournalEnd
			#print the test report
			rlJournalPrintText
			exit 1
		fi

		# CKI kernel set panic_on_oops to 1 by default
		# Disable panic on oops as some kunit tests might trigger oops intentionally
		panic_on_oops=$(sysctl kernel.panic_on_oops | awk '{print$3}')
		rlRun "sysctl kernel.panic_on_oops=0"
	rlPhaseEnd

#-------------------- Run Tests -----------------
	dmesg --clear
	for TEST in "${test_arr[@]}"
	do
		rlPhaseStartTest "running ${TEST}"
			if [[ ${SKIP_TESTS} =~ ${TEST} ]]; then
				rlLog "Skipping $TEST"
				continue
			fi

			modprobe "$TEST" 2>/dev/null
			if [ $? -ne 0 ]; then
				rlLog "Could not install $TEST module, skipping this module"
				continue
			fi
			rlLog "running test $TEST"
		rlPhaseEnd
	done


#------------------ Collect Output --------------
	mkdir -p /tmp/kunit_results/
	cp -r /sys/kernel/debug/kunit/. /tmp/kunit_results/
	for TEST in /tmp/kunit_results/*
	do
		test_name="$(basename "$TEST")"
		# rlFileSubmit doesn't seem to like files with whitespace
		test_name=${test_name// /_}
		rlPhaseStartTest "process ${test_name}"
			if [ -d "${TEST}" ]
			then
				cp "${TEST}/results" "${test_name}.log"
				process_results "${TEST}/results"
				result=$?
				if [ $result -eq 0 ]
				then
					rlPass "process $test_name"
				else
					rlFail "process $test_name"
				fi
				rlFileSubmit "${test_name}.log"
				rm -f "${test_name}.log"
			else
				# no result generated, assume it skipped
				rlLog "no result found, assuming it skipped"
			fi
		rlPhaseEnd
	done

#-------------------- Clean Up ------------------
	rlPhaseStartCleanup
		# Restore panic on oops value
		rlRun "sysctl kernel.panic_on_oops=${panic_on_oops}"
		#remove installed modules and kunit framework
		for TEST in "${test_arr[@]}"
		do
			rmmod "$TEST" 2>/dev/null
		done
		rmmod kunit
		rm -rf /tmp/kunit_results/
	rlPhaseEnd

rlJournalEnd

#print the test report
rlJournalPrintText
