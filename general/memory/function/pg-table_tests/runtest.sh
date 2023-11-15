#!/bin/bash

# include beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

TESTAREA=/mnt/testarea
mkdir -p $TESTAREA

EXPECT_LVL=4
PLVL=""

MAX_USER_VM_4LVL_GiB=$(( 131072 ))

# aarch64 on rhel8.
MAX_USER_VM_3LVL_GiB=$(( 262144 ))

#
# Detect configuration
#
SUPPORT_NO5LVL=0
SUPPORT_LA57=0
SUPPORT_CONFIG_5LVL=0

function detect_configuration()
{
	if grep -q la57 /proc/cpuinfo 2>/dev/null; then
		echo "Detected la57 cpu support"
		SUPPORT_LA57=1
	fi

	if grep -q no5lvl /proc/cmdline 2>/dev/null; then
		echo "Detected no5lvl kernel parameter"
		SUPPORT_NO5LVL=1
	fi

	if grep -q CONFIG_X86_5LEVEL=y /boot/config-"$(uname -r)" 2>/dev/null  ; then
		echo "Detected 5lvl config"
		SUPPORT_CONFIG_5LVL=1
	fi
	if grep -i 'CONFIG_PGTABLE_LEVELS=3' /boot/config-"$(uname -r)" 2>/dev/null; then
		echo "Detected 3lvl config"
		SUPPORT_CONFIG_LVL=3
		EXPECT_LVL=3
	fi

	if [[ $SUPPORT_LA57 -eq 1 &&  $SUPPORT_NO5LVL -eq 0 && $SUPPORT_CONFIG_5LVL -eq 1 ]] ; then
		EXPECT_LVL=5
	fi

	echo "page size: $(getconf PAGE_SIZE)"
	if [[ $EXPECT_LVL -eq 5 ]]; then
		echo "Expecting 5-level pagetables"
		PLVL="5level-paging-$(getconf PAGE_SIZE)"
	elif [ "$SUPPORT_CONFIG_LVL" = "3" ]; then
		echo "Expecting 3-level pagetables"
		PLVL="3level-paging-$(getconf PAGE_SIZE)"
		MAX_USER_VM_4LVL_GiB=$MAX_USER_VM_3LVL_GiB
	else
		if [[ "$(uname -r)" =~ "aarch64" ]]; then
			MAX_USER_VM_4LVL_GiB=$MAX_USER_VM_3LVL_GiB
		fi
		echo "Expecting 4-level pagetables"
		PLVL="4level-paging-$(getconf PAGE_SIZE)"
	fi
}

#
# heap test - malloc
#
function heap_test_malloc()
{
	testlog=${TESTAREA}/heap_test_malloc.log

	echo > $testlog
	echo "Running heap - malloc test... " | tee -a $testlog
	regex="^([0-9]+) GiB allocated."
	if ! output=$(./heap --malloc | tee -a $testlog) ; then
		echo "$? FAILED"  | tee -a $testlog
		rlFail "$? FAILED"
	elif [[ $output =~ $regex ]] ; then
		alloc="${BASH_REMATCH[1]}"
		if [[ $alloc -gt $MAX_USER_VM_4LVL_GiB ]] ; then
			echo "$alloc GiB allocated > $MAX_USER_VM_4LVL_GiB GiB max ${PLVL:0:1}-lvl user VM max" | tee -a $testlog
			echo -e "FAILED" | tee -a $testlog
			rlFail "$alloc GiB allocated > $MAX_USER_VM_4LVL_GiB GiB max ${PLVL:0:1}-lvl user VM max"
		else
			echo "$alloc GiB allocated <= $MAX_USER_VM_4LVL_GiB GiB max ${PLVL:0:1}-lvl user VM max" | tee -a $testlog
			echo -e "PASSED" | tee -a $testlog
		fi
	fi

	rlFileSubmit $testlog
}

#
# heap test - sbrk
#
function heap_test_sbrk()
{
	testlog=${TESTAREA}/heap_test_sbrk.log

	echo > $testlog
	echo "Running heap - sbrk test... " | tee -a $testlog
	regex="^([0-9]+) GiB allocated."
	if ! output=$(./heap --sbrk | tee -a $testlog) ; then
		echo "$? FAILED" | tee -a $testlog
		rlFail "$? FAILED"
	elif [[ $output =~ $regex ]] ; then
		alloc="${BASH_REMATCH[1]}"
		if [[ $alloc -gt $MAX_USER_VM_4LVL_GiB ]] ; then
			echo "$alloc GiB allocated > $MAX_USER_VM_4LVL_GiB GiB max ${PLVL:0:1}-lvl user VM max" | tee -a $testlog
			echo -e "FAILED" | tee -a $testlog
			rlFail "$alloc GiB allocated > $MAX_USER_VM_4LVL_GiB GiB max ${PLVL:0:1}-lvl user VM max"
		else
			echo "$alloc GiB allocated <= $MAX_USER_VM_4LVL_GiB GiB max ${PLVL:0:1}-lvl user VM max" | tee -a $testlog
			echo -e "PASSED" | tee -a $testlog
		fi
	fi

	rlFileSubmit $testlog
}

#
# setting up the mmap tests
#
function setup_mmap_test()
{
	if [[ $EXPECT_LVL -eq 5 ]] ; then
		BEGIN="47"
		END="56"
	#aarch64 on rhel8
	elif [[ $EXPECT_LVL -eq 3 ]]; then
		BEGIN="38"
		END="47"
	else
		BEGIN="37"
		END="46"
	fi
}

#
# mmap+memset+fork test - 1 process, MAP_PRIVATE
#
function mmap_private()
{
	testlog=${TESTAREA}/mmap_private.log

	echo > $testlog
	echo "Running mmap+memset+fork test: 1 process, MAP_PRIVATE..." | tee -a $testlog
	output="$(./mmap+memset+fork --begin "$BEGIN" --end "$END" --map_private --map_anonymous | tee -a $testlog)"

	fail=$?
	regex="read\(.*\) != write_pattern\(.*\)"

	while IFS= read -r ; do
		if [[ $output =~ $regex ]] ; then
			fail=1
			break;
		fi
	done <<< "$output"

	if [[ $fail -eq 1 ]] ; then
		echo -e "FAILED" | tee -a $testlog
		rlFail "FAILED"
	else
		echo -e "PASSED" | tee -a $testlog
	fi

	rlFileSubmit $testlog
}

#
# mmap+memset+fork test - 2 processes, MAP_PRIVATE
#
function mmap_private2()
{
	testlog=${TESTAREA}/mmap_private2.log

	echo > $testlog
	echo "Running mmap+memset+fork test: 2 processes, MAP_PRIVATE..." | tee -a $testlog
	output="$(./mmap+memset+fork --begin "$BEGIN" --end "$END" --fork_child --map_private --map_anonymous | tee -a $testlog)"

	fail=$?
	regex="read\(.*\) != write_pattern\(.*\)"

	while IFS= read -r ; do
		if [[ $output =~ $regex ]] ; then
			fail=1
			break;
		fi
	done <<< "$output"

	if [[ $fail -eq 1 ]] ; then
		echo -e "FAILED" | tee -a $testlog
		rlFail "Failed"
	else
		echo -e "PASSED" | tee -a $testlog
	fi

	rlFileSubmit $testlog
}


# ------ Start Testing ------

rlJournalStart
	rlPhaseStartSetup
		rlRun "detect_configuration"
	rlPhaseEnd

		rlPhaseStartTest "heap test $PLVL"
			rlRun "cc heap.c -o heap"
			rlRun "heap_test_malloc"
			rlRun "heap_test_sbrk"
		rlPhaseEnd

		rlPhaseStartTest "mmap test $PLVL"
			rlRun "cc mmap+memset+fork.c -o mmap+memset+fork"
			rlRun "setup_mmap_test"
			rlRun "mmap_private"
			rlRun "mmap_private2"
		rlPhaseEnd

	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalEnd
