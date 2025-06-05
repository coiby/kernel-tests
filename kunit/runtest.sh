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
	rlLog "processing results from test ${1}"
	rlFileSubmit "${1}"
	# use rlLog instead of `rlRun -l` to avoid the 50 lines limit
	rlLog "$(cat "${test_name}".log)"
	if grep -q "not ok" "$1"; then
		grep "not ok" "$1" >> not_ok.log
		return 1
	else
		return 0
	fi
}

# a list of known broken modules
# used to skip tests that wont be fixed in zstream
is_broken(){
	local test_name=$1
	local skip_string=""

	if rlIsRHEL "<=9.3"; then
		skip_string="test_kasan kasan_test slub_kunit"
	fi

	if rlIsRHEL "9.4"; then
		skip_string="slub_kunit test_kasan kasan_test handshake-test drm_gem_shmem_test dev_addr_lists_test"
	fi

	if rlIsRHEL "9.5"; then
		skip_string="drm_gem_shmem_test drm_buddy_test kasan_test dev_addr_lists_test"
	fi

	if rlIsRHEL ">=9.6" || rlIsCentOS "9"; then
		skip_string="drm_gem_shmem_test drm_buddy_test kasan_test dev_addr_lists_test"
	fi

	if rlIsRHEL ">=10.0" || rlIsCentOS "10"; then
		skip_string="drm_gem_shmem_test drm_format_helper_test drm_hdmi_state_helper_test usercopy_kunit fortify_kunit kasan_test dev_addr_lists_test"
	fi

	if [[ -n "$skip_string" && "$skip_string" =~ $test_name ]]; then
		return 0 # zero indicates true
	fi

	return 1
}

# detect what kunit modules are available in the running release
generate_test_list(){
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
			decompressed_module="$TEMP_DIR/$(basename "$module" .xz)"
			module_name=$(basename "$module" .ko.xz)  # Strip both .ko.xz
		elif [[ "$module" == *.zst ]]; then
			unzstd -c "$module" > "$TEMP_DIR/$(basename "$module" .zst)"
			decompressed_module="$TEMP_DIR/$(basename "$module" .zst)"
			if [[ "$module" == *.ko.zst ]]; then
				module_name=$(basename "$module" .ko.zst)  # Strip both .ko and .zst
			else
				module_name=$(basename "$module" .zst)    # Only strip .zst if needed
			fi
		else
			# If the module is not compressed, copy it to the temp directory
			cp "$module" "$TEMP_DIR/$(basename "$module")"
			decompressed_module="$TEMP_DIR/$(basename "$module")"
			module_name=$(basename "$module" .ko)  # Strip only .ko if needed
		fi

		# Check if the module contains 'kunit_test_suites'
		if objdump -x "$decompressed_module" | grep -q 'kunit_test_suites'; then
			echo "$module_name" >> kunit-tests.list
		fi
	done
}

#Include Beaker environment
. ../cki_lib/libcki.sh || exit 1
. ../kernel-include/runtest.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../cmdline_helper/libcmd.sh || exit 1


# parse SKIP_BROKEN
if [[ -n "${SKIP_BROKEN}" && "${SKIP_BROKEN}" -eq 1 ]]; then
	KUNIT_SKIP_BROKEN=1
else
	KUNIT_SKIP_BROKEN=0
fi

# variables used by beakerlib
TEST="KUNIT"
export PACKAGE="kernel"

rlJournalStart
	if [[ ! -f "./KUNIT_REBOOT_CLEANUP" ]]; then
	# Automotive hardware android bootloader
	# Install abootimg ; Set cmdline param to enable kunit
	if ! systemd-detect-virt &>/dev/null && rpm -qa | grep -q "^kernel-automotive"; then
		if [[ "$REBOOTCOUNT" -eq 0 ]]; then
			rlPhaseStartTest "Install abootimg"
				major=$(grep ^VERSION_ID= /etc/os-release | cut -d = -f 2 | cut -d \" -f 2 | cut -d . -f 1)
				karch=$(arch)
				dnf install -y --nobest --allowerasing --nogpgcheck --repofrompath aboot,https://mirror.stream.centos.org/SIGs/${major}-stream/automotive/${karch}/packages-main/ abootimg
				rlRun "change_cmdline 'kunit.enable=1'"
				rlRun "change_cmdline 'kernel.panic_on_oops=0'"
				rlRun "rstrnt-reboot"
			rlPhaseEnd
		fi
	fi
	# Clean start is a test phase as we want report this as test failure
	# in the setup phase this would be reported as WARN/ERROR
	rlPhaseStartTest "clean-start"
		if [[ -f kunit-tests.list ]]; then
			rlDie "kunit-tests.list already exists. Is this due to reboot after panic?"
		fi
	rlPhaseEnd
#-------------------- Setup ---------------------
	rlPhaseStartSetup
		touch not_ok.log
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
		if ! rpm -q "$module_pkg"; then
			rlDie "${module_pkg} is not installed, aborting test"
		fi
		#test for kunit
		rlRun "modprobe kunit"
		if [ $? -ne 0 ]; then
			rlDie "Could not load KUNIT module, aborting test"
		fi

		generate_test_list

		# Output the result list
		echo "Modules containing 'kunit_test_suites':"
		cat kunit-tests.list
		rlFileSubmit kunit-tests.list
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
		if [ "$TEST" = "kunit" ]; then
			continue
		fi

		rlPhaseStartTest "process ${TEST}"
			if [[ ${SKIP_TESTS} =~ ${TEST} ]]; then
				rlLog "Skipping $TEST"
				continue
			fi

			if [[ $KUNIT_SKIP_BROKEN -eq 1 ]] && is_broken "$TEST"; then
				rlLog "Skipping broken test: $TEST"
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
	rlFileSubmit not_ok.log
	rlPhaseStartCleanup
		# Restore panic on oops value
		rlRun "sysctl kernel.panic_on_oops=${panic_on_oops}"
		#remove kunit framework
		rmmod kunit
		rm -f kunit-tests.list
		rm -f not_ok.log
		if ! systemd-detect-virt &>/dev/null && rpm -qa | grep -q "^kernel-automotive"; then
			# Restore automotive kernel cmdline
			rlRun "change_cmdline '-kunit.enable=1'"
			rlRun "change_cmdline '-kernel.panic_on_oops=0'"
			rlRun "touch KUNIT_REBOOT_CLEANUP"
			rlRun "rstrnt-reboot"
		fi
	fi
	rlPhaseEnd

rlJournalEnd

#print the test report
rlJournalPrintText
