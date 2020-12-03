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
#Include Beaker environment
. ../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Global parameters
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
test_arr=(kunit-test ext4-inode-test list-test sysctl-test mptcp_crypto_test \
	mptcp_token_test)
NUM_TESTS=$((${#test_arr[@]}+2))

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

    TMPFILE=$(mktemp) || exit 1
    OUTFILE=$(mktemp) || exit 1
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
		rmmod $TEST
		#rstrnt-report-result $TEST PASS 1
	fi
    done

#------------------ Collect Output --------------
    dmesg -t > $TMPFILE
    sed -i "s/TAP version 14/1..$NUM_TESTS/g" $TMPFILE
    tappy $TMPFILE &> $OUTFILE
    OUTPUT=$(cat $OUTFILE |tail -1)
    cat $TMPFILE
    rstrnt-report-log -l ${OUTFILE}
    rstrnt-report-log -l ${TMPFILE}
    
#-------------------- Return --------------------   
    #exit 0 if all tests ran 'ok'
    if [[ $OUTPUT == "OK" ]]; then
    	rstrnt-report-result 'KUNIT RESULTS' PASS 0
    else
    	rstrnt-report-result 'KUNIT RESULTS' FAIL 1
    fi
  rlPhaseEnd

#-------------------- Clean Up ------------------
  rlPhaseStartCleanup
    rmmod kunit
  rlPhaseEnd

rlJournalEnd

#print the test report
rlJournalPrintText
