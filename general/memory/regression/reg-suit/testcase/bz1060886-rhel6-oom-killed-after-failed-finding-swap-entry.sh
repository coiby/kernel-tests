#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1060886
#   Description: RHEL 6.4/6.5 experiences oom-killer after failure in finding swap entry
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

function setup_test_env()
{
	rlRun "swapoff -a"
	if [ $? -ne 0 ]; then
		rlLogInfo "LOGINFO: Sorry, swap off failed."
		return 2;
	fi
	rlLogInfo "dd swapfile ..."
	for i in {1..10}
	do
		dd if=/dev/zero of=swapfile-"$i" bs=157280 count=1000
		mkswap swapfile-"$i"
		rlRun "swapon swapfile-\"$i\" -p 1" 0-254
	done
	PRIORITY=`cat /proc/swaps | sed -n '2p' | awk '{print $5}'`
	if [ $PRIORITY -ne 1 ]; then
		rlLogInfo "LOGINGO: Sorry, set swapfile failed."
		return 1;
	fi
	PANIC_ON_OOM=`cat /proc/sys/vm/panic_on_oom`
	rlRun "echo 1 >/proc/sys/vm/panic_on_oom" 0 "Let the system panic when oom appears."

}

function cleanup()
{

	rlRun "echo \"$PANIC_ON_OOM\" > /proc/sys/vm/panic_on_oom" 0-254

	for i in {1..10}
	do
		rlRun "swapoff swapfile-$i" 0-254
	done

	rlRun "swapon" 0-254
	rm swapfile*
}

function bz1060886()
{
	local cmdline="mem=2G"
	local reboot_flag="$DIR_DEBUG/${FUNCNAME}_F"
	local reboot_flag_restore="$DIR_DEBUG/${FUNCNAME}_S"
	case $(rlGetPrimaryArch) in
		x86_64)

			if [ -f $reboot_flag_restore ];then
				rlRun "cat /proc/cmdline|grep $cmdline" 1 "mem=2G should not include in kernel cmdline now!!!"
				return 1;
			fi

			if [ ! -f $reboot_flag ];then
				rlRun "CpuVendor=$(lscpu |grep -m 1 "Vendor ID" |awk -F ':'  '{print $2}'|sed 's/ //g')"
				rlRun "CpuFamily=$(lscpu |grep -m 1 "CPU family" |awk -F ':' '{print $2}'|sed 's/ //g')"
				rlRun "Model=\"$(lscpu |grep -m 1 "Model" |awk -F ':' '{print $2}'|sed 's/ //g')\""
				rlRun "NumaNode=$(lscpu |grep -m 1 "NUMA node" |awk -F ':' '{print $2}'|sed 's/ //g')"

				rlRun "TotalMem=\"$(free -m |grep Mem |awk '{print $2}')\"" 0-254
				((TotalMem < 2156)) && rlLogWarning "There is no 2G memory for testing.Skip the test." && return 1;

				rlLogInfo "$FUNCNAME is excuting before reboot"
				rlRun "gcc -Wall -o $DIR_BIN/bz1060886 $DIR_SOURCE/bz1060886.c"
				cp bz1060886 ..
				[ $? -ne 0 ] && return 1;
				rlRun "grubby --args=\"$cmdline\" --update-kernel=$(grubby --default-kernel)"
				rlRun "touch $reboot_flag" 0 "touch reboot flag file and reboot sys to enable cmdline"
				rlRun "echo $REBOOTCOUNT > $reboot_flag"
				rhts-reboot
			fi
			local reboot_times=$(cat reboot_flag)
			(( (reboot_times - $REBOOTCOUNT) > 2 )) && rlRun "Test has failed.Please check the panic from console/dmesg" && return 1;
			if setup_test_env;then
				rlLogInfo "Executing the reproducer for 1000 times"
				for i in {1..1000}
				do 
					$DIR_BIN/bz1060886 -s 1024; sleep 1; 
				done
			fi
			cleanup
			rlRun "grubby --remove-args=\"$cmdline\" --update-kernel=$(grubby --default-kernel)"
			touch $reboot_flag_restore
			rhts-reboot
	    		;;
		*)
			rlLogInfo "$(uname -m) is not intended to be tested."
	    		;;
	esac
}
