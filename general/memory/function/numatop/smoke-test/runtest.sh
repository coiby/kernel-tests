#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /tools/numatop/Sanity/smoke-test
#   Description: It generates some NUMA load and checks whether numatop sees it.
#   Author: Michael Petlan <mpetlan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

CLONE_ATTEMPTS_COUNT=25
TmpDir=$(mktemp -d)

rlJournalStart
	rlPhaseStartSetup
		rlRun "cp mgen.tar.gz $TmpDir/"
		rlRun "cp 0001-fix-numatop-build-error-on-rhel10.patch $TmpDir/"
		rlRun "pushd $TmpDir"
		NUMATOP_PACKAGE=`rpm -q numatop`
		if [ $? -eq 0 ]; then
			rlLog "WE USE RHEL PACKAGE: $NUMATOP_PACKAGE"
		else
			rlLogWarn "NO RHEL PACKAGE FOR NUMATOP AVAILABLE!"

		fi
		# we need to build mgen for test
		for (( i=0; i<$CLONE_ATTEMPTS_COUNT; i++ )); do
			echo "Trying to clone the repo....... take $i..."
			git clone --depth 1 https://gitlab.com/redhat/centos-stream/tests/kernel/core/numatop.git
			if [ $? -eq 0 ]; then
				echo "I have been able to clone the repo."
				REPO_CLONED=1
				break
			fi
			sleep 8
		done
		if [ $REPO_CLONED -ne "1" ]; then
			rlFail "I have not been able to clone the repo in $ATTEMPTS_COUNT takes....."
		else
			rlPass "The REPO has been cloned!"
		fi
		rlRun "cd numatop"
		rlRun "git apply ../0001-fix-numatop-build-error-on-rhel10.patch"
		rlRun "mkdir m4"
		rlRun "sh autogen.sh"
		rlRun "./configure"
		rlRun "make"
		rlAssertExists "numatop"
		#rlRun "cp numatop /usr/local/bin/"
		rlRun "cp mgen /usr/local/bin/"
		rlRun "which numatop"
		rlRun "cd .."

		# log something about the CPU
		lscpu | while read line; do  rlLog "$line"; done

		# log kernel version
		rlLog "`uname -r`"

		NUMA_NODES=`lscpu -e=node | grep -v NODE | sort -u | wc -l`
		CPU_FROM_NODE0=`lscpu -e=node,cpu | egrep '^[[:space:]]*0' | awk '{print $2}' | head -n 1`
		CPU_FROM_NODE1=`lscpu -e=node,cpu | sed '1d' | egrep '^[[:space:]]*[1-9]+' | awk '{print $2}' | head -n 1`
	rlPhaseEnd

	rlPhaseStartTest "check machine"
		#rlRun "timeout 10 numatop"
		numatop > /dev/null &
		NUMATOP_PID=$!
		sleep 5
		kill $NUMATOP_PID
		if [ $? -ne 0 ]; then
			rlPass "This machine does not support numatop"
			exit 0
		fi
	rlPhaseEnd

	rlPhaseStartTest "LMA test"
		mgen -a $CPU_FROM_NODE0 -c $CPU_FROM_NODE0 -t 60 > /dev/null &
		MGEN_PID=$!
		sleep 5
		rlLog "Running mgen with PID = $MGEN_PID"
		numatop -l 0 -d lma.log > /dev/null < /dev/null 2> /dev/null &
		NUMATOP_PID=$!
		rlLog "Running numatop with PID = $NUMATOP_PID"
		sleep 30
		rlRun "kill $NUMATOP_PID"
		sleep 5
		rlRun "kill $MGEN_PID"
		LMA_RESULT=`cat lma.log | grep mgen | tail -n 1 | awk '{print $4;}'`
		IS_ENOUGH=`echo "$LMA_RESULT > 5000" | bc -l`
		if [ $IS_ENOUGH -eq 1 ]; then
			rlPass "Measured value for LMA looks sane [ $LMA_RESULT ]"
		else
			rlFail "Measured value for LMA looks bogus [ $LMA_RESULT ]"
		fi
	rlPhaseEnd

	if [ $NUMA_NODES -ge 2 ]; then
		rlPhaseStartTest "RMA test"
			mgen -a $CPU_FROM_NODE0 -c $CPU_FROM_NODE1 -t 60 >/dev/null &
			MGEN_PID=$!
			sleep 5
			rlLog "Running mgen with PID = $MGEN_PID"
			numatop -l 0 -d rma.log > /dev/null < /dev/null 2> /dev/null &
			NUMATOP_PID=$!
			rlLog "Running numatop with PID = $NUMATOP_PID"
			sleep 30
			rlRun "kill $NUMATOP_PID"
			sleep 5
			rlRun "kill $MGEN_PID"
			RMA_RESULT=`cat rma.log | grep mgen | tail -n 1 | awk '{print $3;}'`
			IS_ENOUGH=`echo "$RMA_RESULT > 5000" | bc -l`
			if [ $IS_ENOUGH -eq 1 ]; then
				rlPass "Measured value for RMA looks sane [ $RMA_RESULT ]"
			else
				rlFail "Measured value for RMA looks bogus [ $RMA_RESULT ]"
			fi
		rlPhaseEnd
	fi

	rlPhaseStartCleanup
		rlRun "popd"
		rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
