#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: mm proactive_compaction feature test
# Author: Li Wang <liwang@redhat.com>

. /usr/bin/rhts-environment.sh      || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

OUTPUTFILE=${OUTPUTFILE:-/mnt/testarea/outputfile}
TASKID=${TASKID:-UNKNOWN}

function supporting_check()
{
	local rhel=$(grep -Eo '[0-9]+.[0-9]+' /etc/redhat-release)
	if (echo ${rhel} "8.4" | awk '($1>=$2){exit 1}') then
		echo "mm proactive_compaction has not been supported on rhel${rhel}" | tee -a $OUTPUTFILE
		rstrnt-report-result Test_Skipped PASS 99
		exit 0
	fi

	if [ -e /proc/sys/vm/compaction_proactiveness ]; then
		compaction_proactiveness=$(cat /proc/sys/vm/compaction_proactiveness)
	else
		echo "FAIL: /proc/sys/vm/compaction_proactiveness is not exist" | tee -a $OUTPUTFILE
		exit 1
	fi
}

function set_compaction_proactiveness()
{
	local proa=$1
	rlRun "echo ${proa} > /proc/sys/vm/compaction_proactiveness"
	rlRun "grep -q ${proa} /proc/sys/vm/compaction_proactiveness"
}

function mm_compaction_test()
{
	local mem_chunks1_head
	local mem_chunks1_tail
	local mem_chunks2_head
	local mem_chunks2_tail

	free -h | tee -a $OUTPUTFILE
	cat /proc/buddyinfo | tee -a $OUTPUTFILE

	./mem-frag-test &
	pid=$(pidof mem-frag-test)
	if [ -z "$pid" ]; then
		echo "mem-frag-test didn't run, let's skip the test" | tee -a $OUTPUTFILE
		rstrnt-report-result Test_Skipped PASS 99
		exit 0
	fi

	echo ""
	echo "------- vm.compaction_proactiveness=0 --------"   | tee -a $OUTPUTFILE
	set_compaction_proactiveness 0
	sleep 60
	cat /proc/buddyinfo > buddyinfo1 && cat buddyinfo1 | tee -a $OUTPUTFILE
	mem_chunks1_head=$(cat buddyinfo1 | awk '{sum += $5} END {print sum}')
	mem_chunks1_tail=$(cat buddyinfo1 | awk '{sum += $NF + $(NF-1) + $(NF-2) + $(NF-3) + $(NF-4)} END {print sum}')
	echo "mem_chunks1_head = $mem_chunks1_head, mem_chunks1_tail = $mem_chunks1_tail" | tee -a $OUTPUTFILE

	echo ""

	echo "------- vm.compaction_proactiveness=100 --------"   | tee -a $OUTPUTFILE
	set_compaction_proactiveness 100
	sleep 60
	cat /proc/buddyinfo > buddyinfo2 && cat buddyinfo2 | tee -a $OUTPUTFILE
	mem_chunks2_head=$(cat buddyinfo2 | awk '{sum += $5} END {print sum}')
	mem_chunks2_tail=$(cat buddyinfo2 | awk '{sum += $NF + $(NF-1) + $(NF-2) + $(NF-3) + $(NF-4)} END {print sum}')
	echo "mem_chunks2_head = $mem_chunks2_head, mem_chunks2_tail = $mem_chunks2_tail" | tee -a $OUTPUTFILE
	echo ""

	killall mem-frag-test >/dev/null 2>&1

	if [ "$mem_chunks1_head" -lt "$mem_chunks2_head" ]; then
		return 0
	elif [ "$mem_chunks1_tail" -gt "$mem_chunks2_tail" ]; then
		return 0
	else
		return 1
	fi
}


# ----- Test Start ------
rlJournalStart

rlPhaseStartSetup
	# remove the ballon driver and disable swap so there is no help
	# coming to compaction when fragmentation sets in
	vb_module=0 && lsmod | grep -q virtio_balloon && vb_module=1
	if [ $vb_module -eq 1 ]; then
		rlRun "rmmod virtio_balloon"
	fi
	rlRun "swapoff -a"

	rlRun "supporting_check"
rlPhaseEnd

rlPhaseStartTest
	rlRun "mm_compaction_test" 0 "Expect mm_compaction_test return 0, PASS"
rlPhaseEnd

rlPhaseStartCleanup
	if [ $vb_module -eq 1 ]; then
		rlRun "modprobe virtio_balloon"
	fi
	rlRun "swapon -a"
	rlRun "echo $compaction_proactiveness > /proc/sys/vm/compaction_proactiveness"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
