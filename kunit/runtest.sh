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
	sed -i '/^S/d' "$1" #remove all empty lines
	sed -i 's/^[ \t]*//' "$1" #remove all leading whitespace
	sed -i '/^#/d' "$1" #remove comments
	sed -i '$d' "$1" #remove last line.
	sed -i '/^\(ok\|not ok\|1..\)/!d' "$1" #removeall but 1..N and ok/not ok
	uniq "$1" > "$TMPFILE"  #remove dup

	tappy "$TMPFILE" &> "$OUTFILE"
        RESULT_OUTPUT=$(cat "$OUTFILE" |tail -1)
	if [ "$RESULT_OUTPUT" = "OK" ]; then
		return 0
	else
		return 1
	fi
}

#Include Beaker environment
. ../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# variables used by beakerlib
TEST="KUNIT"
PACKAGE="kernel"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Global parameters
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# When rebasing create a new array at the current release number (eg rhel8.5)
# Then add a check for the proper tag number

tag=$(uname -rm | grep -o "\-.*.el8")
el8=$( echo "$tag" | grep -o ".el8" )
version=$( echo "$tag" | sed 's/\-\(.*\).el8/\1/')

#currently only supports rhel 8
if [ "$el8" != ".el8" ]; then
	rlLog "RHEL8 Varient not detected. currently only supports =>rhel8.4"
	rstrnt-report-result $TEST SKIP
	exit 0
fi

test_arr=(kunit-test ext4-inode-test list-test sysctl-test mptcp_crypto_test \
	mptcp_token_test bitfield_kunit cmdline_kunit property-entry-test \
	qos-test resource_kunit soc-topology-test string-stream-test \
	test_linear_ranges test_bits test_kasan)

rlJournalStart
#-------------------- Setup ---------------------
  rlPhaseStartSetup
  #install tappy
    pip3 install tap.py
    if [ $? -ne 0 ]; then
	rlLog "Pip unable to install tap.py, aborting test"
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    fi

    # kunit module was added on kernel 4.18.0-279 (BZ#1900119)
    rlCmpVersion `uname -r` "4.18.0-279.el8"
    if [ $? -eq 2 ]; then
        # kernel is too old to support kunit module
        rstrnt-report-result $TEST SKIP
        rlPhaseEnd
        rlJournalEnd
        #print the test report
        rlJournalPrintText
        exit 0
    fi
    #test for kunit
    modprobe kunit
    if [ $? -ne 0 ]; then
        rlFail "Could not install KUNIT module, aborting test"
        rstrnt-report-result $TEST FAIL
        rlPhaseEnd
        rlJournalEnd
        #print the test report
        rlJournalPrintText
        exit 1
    fi

  rlPhaseEnd

#-------------------- Run Tests -----------------
  rlPhaseStartTest
  dmesg --clear
    for TEST in ${test_arr[*]}
    do
	rlLog "running test $TEST"
	modprobe "$TEST"
	if [ $? -ne 0 ]; then
		rlLog "Could not install $TEST module, skipping this module"
	fi
    done

#------------------ Collect Output --------------
    mkdir -p /tmp/kunit_results/
    cp -r /sys/kernel/debug/kunit/. /tmp/kunit_results/
    for TEST in /tmp/kunit_results/*
    do
	if [ -d "${TEST}" ]
	then
		test_name="$(basename "$TEST")"
		cp "${TEST}/results" "${TEST}/${test_name}.log"
		process_results "${TEST}/results"
		result=$?	
		if [ $result -eq 0 ]
		then
			rstrnt-report-result -o "${TEST}/${test_name}.log" "$test_name" PASS 0
                else
			rstrnt-report-result -o "${TEST}/${test_name}.log" "$test_name" FAIL 1
                fi
	fi
    done
  rlPhaseEnd

#-------------------- Clean Up ------------------
  rlPhaseStartCleanup
  #remove installed modules and kunit framework
  for TEST in ${test_arr[*]}
  do
	  rmmod "$TEST"
  done
  rmmod kunit
  rm -rf /tmp/kunit_results/
  rlPhaseEnd

rlJournalEnd

#print the test report
rlJournalPrintText
