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
	uniq "$1" > "$TMPFILE"  #remove dup
	tappy "$TMPFILE" &> "$OUTFILE"
        RESULT_OUTPUT=$(cat "$OUTFILE" |tail -1)
	if [ "$RESULT_OUTPUT" = "OK" ]; then
		return 1
	else
		return 0
	fi
}

#Include Beaker environment
. ../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Global parameters
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# TODO: find a better way to determine available tests  
test_arr=(kunit-test ext4-inode-test list-test sysctl-test mptcp_crypto_test \
	mptcp_token_test)

rlJournalStart
#-------------------- Setup ---------------------
  rlPhaseStartSetup
  #install tappy
    pip3 install tap.py
    if [ $? -ne 0 ]; then
	rlLog "Pip unable to install tap.py, aborting test"
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    fi

    #test for kunit
    modprobe kunit
    if [ $? -ne 0 ]; then
	rlLog "Could not install KUNIT module, aborting test"
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    fi

  rlPhaseEnd

#-------------------- Run Tests -----------------
  rlPhaseStartTest
  dmesg --clear
    for TEST in ${test_arr[*]}
    do
	rlLog "running test $TEST"
	modprobe $TEST
	if [ $? -ne 0 ]; then
		rlLog "Could not install $TEST module, skipping this module"
		#rstrnt-report-result $TEST SKIP 0
	else
		#rmmod $TEST
		#rstrnt-report-result $TEST PASS 1
	fi
    done

#------------------ Collect Output --------------
    mkdir -p /tmp/kunit_results/
    cp -r /sys/kernel/debug/kunit/. /tmp/kunit_results/
    for TEST in /tmp/kunit_results/*
    do
	if [ -d ${TEST} ]
	then
		process_results ${TEST}/results
		if [ $? -ne 0 ]
		then
			rstrnt-report-result $TEST PASS 1
                else
			rstrnt-report-result $TEST FAIL 0
                fi
		rstrnt-report-log -l "${TEST}/results"
	fi
    done
  rlPhaseEnd

#-------------------- Clean Up ------------------
  rlPhaseStartCleanup
  #remove installed modules and kunit framework
  for TEST in "${test_arr[*]}"
  do
	  rmmod "$TEST"
  done
  rmmod kunit
  rlPhaseEnd

rlJournalEnd

#print the test report
rlJournalPrintText
