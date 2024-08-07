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

rlJournalStart
#-------------------- Setup ---------------------
	rlPhaseStartSetup
		#install tappy
		pip3 install tap.py
		if [ $? -ne 0 ]; then
			rlLog "Pip unable to install tap.py, aborting test"
			rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
			rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
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
		dnf install -y "${module_pkg}"
		if ! rpm -q $module_pkg; then
			echo "FAIL: ${module_pkg} is not installed, aborting test"
			rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
			rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
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

		# generate test list from modules-internal
		# Directory containing the kernel modules
		MODULE_DIR="/lib/modules/$(uname -r)/internal/"

		# Temporary directory for decompression
		TEMP_DIR=$(mktemp -d)

		# Function to clean up temporary directory
		cleanup() {
				rm -rf "$TEMP_DIR"
		}
		trap cleanup EXIT

		# Iterate over each compressed kernel module found
		find "$MODULE_DIR" -type f -name '*.ko*' | while IFS= read -r module; do

			# Determine the extension to handle decompression
			if [[ "$module" == *.xz ]]; then
				unxz -c "$module" > "$TEMP_DIR/$(basename "$module" .xz)"
			else
				# If the module is not compressed, copy it to the temp directory
				cp "$module" "$TEMP_DIR/$(basename "$module")"
			fi

			# The decompressed or copied module file
			decompressed_module="$TEMP_DIR/$(basename "$module" .xz)"

			# Check if the module contains 'kunit_test_suites'
			if objdump -x "$decompressed_module" | grep -q 'kunit_test_suites'; then
				module_name=$(basename "$module" .ko.xz)
				echo "$module_name" >> kunit-tests.list
			fi
		done

		# Output the result list
		echo "Modules containing 'kunit_test_suites':"
		cat kunit-tests.list

		# load kunit module names into a array
		readarray -t test_arr < kunit-tests.list

		# CKI kernel set panic_on_oops to 1 by default
		# Disable panic on oops as some kunit tests might trigger oops intentionally
		panic_on_oops=$(sysctl kernel.panic_on_oops | awk '{print$3}')
		rlRun "sysctl kernel.panic_on_oops=0"
	rlPhaseEnd

#-------------------- Run Tests -----------------
	dmesg --clear
	for TEST in "${test_arr[@]}"
	do
		#the kunit module is not a test
		if [ $TEST = "kunit" ]; then
			continue
		fi

		rlPhaseStartTest "process ${TEST}"
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
			monitor_dir="/sys/kernel/debug/kunit"
			# Infinite loop to monitor the directory
			while true; do
				# Check if there are any directories in the monitor directory
				if [ "$(find "$monitor_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)" -gt 0 ]; then
					all_dirs_have_results=true

					# Check if all directories have the results file
					for dir in "$monitor_dir"/*/; do
						if [ ! -f "$dir/results" ]; then
							rlLog "Directory $dir found, but no results file yet"
							all_dirs_have_results=false
							break
						fi
					done

					if $all_dirs_have_results; then
						# Process each directory that has results
						for dir in "$monitor_dir"/*/; do
							rlLog "Results found in $dir"
							test_name="$(basename "$dir")"
							test_name=${test_name// /_}
							cp "$dir/results" "${test_name}.log"

							rlFileSubmit "${test_name}.log"
							rlRun -l "cat ${test_name}.log"
							process_results "${test_name}.log"
							result=$?
							if [ $result -eq 0 ]; then
								rlPass "process $test_name"
							else
								rlFail "process $test_name"
							fi
							rm -f "${test_name}.log"
						done
					fi
				else
					rlLog "No directories found in $monitor_dir, waiting..."
				fi

				# If all directories have results, break the loop
				if $all_dirs_have_results; then
					break
				fi

				sleep 1
			done
			rmmod "$TEST" 2>/dev/null
		rlPhaseEnd
	done


#-------------------- Clean Up ------------------
	rlPhaseStartCleanup
		# Restore panic on oops value
		rlRun "sysctl kernel.panic_on_oops=${panic_on_oops}"
		#remove kunit framework
		rmmod kunit
	rlPhaseEnd

rlJournalEnd

#print the test report
rlJournalPrintText
