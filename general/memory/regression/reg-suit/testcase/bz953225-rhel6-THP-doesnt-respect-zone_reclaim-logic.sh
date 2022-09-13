#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 953225
#   Description: 953225 - THP does not respect zone_reclaim logic
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cur_path=$(pwd)
zone_reclaim_mode=
drop_caches=
thp_enabled="always"
cpus=

function compile_tools()
{
	### compile the C program ###
	if [ -f $DIR_SOURCE/bz953225-breakthp.c ] && [ -f $DIR_SOURCE/bz953225-usemem.c ]; then
		rlRun "gcc -o $DIR_BIN/breakthp $DIR_SOURCE/bz953225-breakthp.c"
		retval_f=$?
		rlRun "gcc -o $DIR_BIN/usemem $DIR_SOURCE/bz953225-usemem.c"
		retval_s=$?
		if [ ! $retval_f = 0 ] || [ ! $retval_s = 0 ];then
			return 1;
		fi
	else
		echo "LOGINFO: Sorry,$(pwd)breakthp.c or $(pwd)usemem.c not exist."
		return 1;
	fi
}

function setup_test_env()
{
	local node0_size node1_size
	tmp=`numactl -H | sed -n '5p' | cut -d ' ' -f 6`
	if [ "XXX"${tmp} = "XXX" ]; then
		rlLogWarning "WARN: The case need 2 numa nodes and 6 cpus at least, \
Please re-run the case on the requriment machine."
		return 1;
	fi
	node0_size=`numactl -H | sed -n '3p' | cut -d ' ' -f 4`
	node1_size=`numactl -H | sed -n '6p' | cut -d ' ' -f 4`
	if [ $node0_size -lt 4096 -o $node1_size -lt 4096 ]; then
		rlLogWarning "WARN: At least 4096M on each node is required, \
node0=${node0_size}M, node1=${node1_size}M"
		return 1;
	fi

	# Get 6 cpus from the output of numactl
	cpus=`numactl -H | sed -n '2p' | cut -d ' ' -f 4 && \
	      numactl -H | sed -n '2p' | cut -d ' ' -f 5 && \
	      numactl -H | sed -n '2p' | cut -d ' ' -f 6 && \
	      numactl -H | sed -n '5p' | cut -d ' ' -f 4 && \
	      numactl -H | sed -n '5p' | cut -d ' ' -f 5 && \
	      numactl -H | sed -n '5p' | cut -d ' ' -f 6`

	if ! compile_tools;then
		return 2;
	fi

	### set the env for testing ###
	rlRun "zone_reclaim_mode=`cat /proc/sys/vm/zone_reclaim_mode`"
	rlRun "echo 1 > /proc/sys/vm/zone_reclaim_mode"

	drop_caches=`cat /proc/sys/vm/drop_caches`
	rlRun "echo 3 > /proc/sys/vm/drop_caches"
	local thp_file="/sys/kernel/mm/transparent_hugepage/enabled"
	rlRun -l "cat /sys/kernel/mm/transparent_hugepage/enabled" 0-255
	if ! grep never $thp_file;then
		rlLogWarning "Thp can't be forbidden. how should i do. Escapte from the aweful env now."
		return 1
	fi
	rlRun "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
}

function cleanup()
{
	rlLogInfo "Clean up the test env."
	echo "$zone_reclaim_mode" > /proc/sys/vm/zone_reclaim_mode
	echo "$drop_caches" > /proc/sys/vm/drop_caches
	echo "$thp_enabled" > /sys/kernel/mm/transparent_hugepage/enabled
}

function test_running()
{
	rlLogInfo "Executing the reproducer on numabinded cpus"
	for i in $cpus; do
		echo "LOGINFO: Start to run $ numactl --physcpubind=$i $DIR_BIN/breakthp 1024 2048 4 60"
		numactl --physcpubind=$i $DIR_BIN/breakthp 1024 2048 4 60  2>&1 > /dev/null &
	done

	echo "LOGINFO: sleeping 1..."
	sleep 1

	echo
	for i in $cpus; do
		echo "LOGINFO: Start to run $numactl --physcpubind=$i ./usemem 1024 15"
		numactl --physcpubind=$i $DIR_BIN/usemem 1024 15 2>&1 > /dev/null &
	done
}

function check_the_output()
{
	rlLogInfo "LOGINFO: Sleeping 10s to wait usemem"

	sleep 10

	rlLogInfo "LOGINFO: The output of ./numa-maps -n usemem"
	$DIR_SOURCE/numa-maps -n usemem  | tee test_case_report.txt

	### to judge the data ###
	for i in `seq 2 7`; do

		N0=`awk '{print $6}' test_case_report.txt | sed -n ''$i'p'`

		if [[ "$N0" = "1.00G" ]]; then
			continue
		elif [[ "$N0" = "0" ]]; then
			continue
		else
			rlFileSubmit  test_case_report.txt
			rlAssert0 "FAIL: Test case failed" 1
			return 1;
		fi
	done

	rlLogInfo "LOGINFO: Test case PASS!"
}

function main()
{
	if setup_test_env;then
		test_running
		check_the_output
	else
		rlLogWarning "Test env setpu failed!!"
		mark_skip bz953225 "2 numa and 6 cpus are needed to test the bug!"
	fi
	cleanup
}

function bz953225()
{
	if ! rlIsRHEL 6 7;then
		rlLogInfo "For rhel6 and rhel7"
		mark_skip "bz953225" "For rhel6 and rhel7"
		return 
	fi
	case $(rlGetPrimaryArch) in
		x86_64)
			main
	    		;;
		*)
			rlLogInfo "$(uname -m) is not intended to be tested."
			mark_skip "bz953225" "$(uname -m) is not intended to be tested."
	    		;;
	esac
}
