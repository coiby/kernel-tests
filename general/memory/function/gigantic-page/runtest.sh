#!/bin/bash

# Summary: Testing gigantic pages allocation
# Author: Li Wang <liwang@redhat.com>
# ---------------------------------------

# Enable TMT testing for RHIVOS
. ../../../cki_lib/libcki.sh

. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

OUTPUTFILE=${OUTPUTFILE:-/mnt/testarea/outputfile}

# OSTree cannot use /mnt/testarea/ as $tmpdir since it is not a permanet storage
if stat /run/ostree-booted > /dev/null 2>&1; then
	OUTPUTFILE=$PWD/runtest.log
fi

TASKID=${TASKID:-UNKNOWN}
ARCH=${ARCH:-$(arch)}
NODES=$(numactl -H | grep available | cut -d ' ' -f 2)

tmpdir=$(dirname $OUTPUTFILE)/gigantic_$TASKID

function system_check()
{
	TESTSKIP=0

	local rhel=$(grep -Eo '[0-9]+.[0-9]+' /etc/redhat-release)
	if (echo ${rhel} "7.0" | awk '($1>$2){exit 1}') then
		echo "gigantic page allocation is only supported on RHEL7" | tee -a $OUTPUTFILE
		TESTSKIP=1
	fi

	if [ ${ARCH} != "x86_64" ]; then
		echo "Now only test on X86_64 system arch" | tee -a $OUTPUTFILE
		TESTSKIP=1
	fi

	grep -q hugetlbfs  /proc/filesystems
	if [ $? -ne 0 ]; then
		echo "hugetlbfs not found in /proc/filesystems" | tee -a $OUTPUTFILE
		TESTSKIP=1
	fi

	grep -q 'pdpe1gb' /proc/cpuinfo
	if [ $? -ne 0 ]; then
		echo "This box doesn't support the gigantic page allocation" |tee -a $OUTPUTFILE
		TESTSKIP=1
	fi

	if [ $NODES -lt 2 ]; then
		echo "The NUMA NODES should be more than 2" |tee -a $OUTPUTFILE
		TESTSKIP=1
	fi

	if [ $TESTSKIP -eq 1 ]; then
		rstrnt-report-result Test_Skipped PASS 99
		rlPhaseEnd
		rlJournalPrintText
		rlJournalEnd
		exit 0
	fi
}

function get_gigantic_parameter()
{
	export GIGANTIC=$(sed -n  -e 's/"\(.*\)"\(.*\)/\1/g' -e '1p' $tmpdir/gigantic_parameter.txt)
	export GIGANTIC_TEST=$(sed -n  -e 's/"\(.*\)"\(.*\)/\2/g' -e '1p' $tmpdir/gigantic_parameter.txt)
	rlRun "sed -i '1d' $tmpdir/gigantic_parameter.txt"
}

# ------ Test Start -------
rlJournalStart

# ------run only once -----
if [ ! -d $tmpdir ]; then
	rlPhaseStartSetup
		rlRun "system_check"
		rlRun "mkdir -p $tmpdir"
		rlRun "pushd $tmpdir"
cat <<EOF >$tmpdir/gigantic_parameter.txt
"hugepagesz=1G default_hugepagesz=1G"test0
"hugepagesz=1G hugepages=2"test1
"hugepagesz=1G default_hugepagesz=1G hugepages=2"test2
"stop"test3
"exit"test0
EOF
		rlRun "popd"
	rlPhaseEnd
fi
# --------------------------

rlPhaseStartTest
	rlRun "get_gigantic_parameter"
	if [ -z "$GIGANTIC" ]; then
		rlFail "GIGANTIC parameter is empty."
	fi

	case $GIGANTIC_TEST in
		test0)
			# Do nothing here, just for kernel parameter updating.
			;;
		test1)
			rlRun "echo 1 > /proc/sys/vm/compact_memory"

			rlRun "echo 1 > /proc/sys/vm/nr_hugepages"
			rlRun "grep -q 1 /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"

			rlRun "echo 0 > /proc/sys/vm/nr_hugepages"
			rlRun "grep -q 0 /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"

			rlRun "echo 1 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
			rlRun "grep -q 1 /proc/sys/vm/nr_hugepages"

			rlRun "echo 0 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
			rlRun "grep -q 0 /proc/sys/vm/nr_hugepages"

			for i in $(seq $NODES); do
				i=$(( $i - 1 ))

				if [ -d /sys/devices/system/node/node${i}/hugepages/ ]; then
					rlRun "echo 1 > /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"
					rlRun "grep -q 1 /proc/sys/vm/nr_hugepages"
					rlRun "grep HugePages_Total /proc/meminfo | grep -q 1"
					rlRun "grep -q 1 /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
					rlRun "grep -q 1 /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages"
					rlRun "grep -q 1 /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"

					rlRun "echo 0 > /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"
					rlRun "grep -q 0 /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"
				else
					rlLogInfo "The /sys/devices/system/node/node${i}/hugepages/ is not exist"
				fi
			done


			gigantic_pages=0

			rlRun "echo 2 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
			rlRun "grep -q 2 /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
			rlRun "grep -q 2 /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages"

			for i in $(seq $NODES); do
				i=$(( $i - 1 ))
				[ -d /sys/devices/system/node/node${i}/hugepages/ ] &&
				gigantic_pages=$(( $gigantic_pages + $(cat /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages) ))
			done

			if [ $gigantic_pages -ne 2 ]; then
				rlFail "Failed to allocate 2 gigantic pages"
			fi

			rlRun "echo 0 > /proc/sys/vm/nr_hugepages"
			;;
		test2)
			rlRun "lsmem"
			rlRun "echo 1 > /proc/sys/vm/compact_memory"

			rlRun "grep -q 0 /proc/sys/vm/nr_hugepages"
			rlRun "grep HugePages_Total /proc/meminfo | grep -q 0"
			rlRun "grep -q 2 /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
			rlRun "grep -q 2 /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages"

			for i in $(seq $NODES); do
				i=$(( $i - 1 ))

				if [ -d /sys/devices/system/node/node${i}/hugepages/ ]; then
					rlRun "echo 0 > /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"
					rlRun "grep -q 0 /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"
				else
					rlLogInfo "The /sys/devices/system/node/node${i}/hugepages/ is not exist"
				fi
			done

			rlRun "grep -q 0 /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
			;;
		test3)
			rlRun "grep -q 2 /proc/sys/vm/nr_hugepages"
			rlRun "grep HugePages_Total /proc/meminfo | grep -q 2"
			rlRun "grep -q 2 /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
			rlRun "grep -q 2 /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages"

			for i in $(seq $NODES); do
				i=$(( $i - 1 ))

				if [ -d /sys/devices/system/node/node${i}/hugepages/ ]; then
					rlRun "echo 0 > /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"
					rlRun "grep -q 0 /sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB/nr_hugepages"
				else
					rlLogInfo "The /sys/devices/system/node/node${i}/hugepages/ is not exist"
				fi
			done

			rlRun "grep -q 0 /proc/sys/vm/nr_hugepages"
			;;
	esac

	# setting kernel parameters
	if [ "$GIGANTIC" = "stop" ] || [ "$GIGANTIC" = "exit" ]; then
		rlRun "grubby --update-kernel=DEFAULT --remove-args=\"hugepagesz=1G default_hugepagesz=1G hugepages=2\""
	else
		rlRun "grubby --update-kernel=DEFAULT --remove-args=\"hugepagesz=1G default_hugepagesz=1G hugepages=2\""
		rlRun "grubby --update-kernel=DEFAULT --args=\"$GIGANTIC\""
	fi
rlPhaseEnd

if [ "$GIGANTIC" != "exit" ]; then
	rstrnt-reboot
fi

rlPhaseStartCleanup
	rlRun "rm -r $tmpdir"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
