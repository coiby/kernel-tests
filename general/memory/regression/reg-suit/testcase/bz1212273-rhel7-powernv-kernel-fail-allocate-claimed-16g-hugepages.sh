#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1212273
#   Arch: ppc64le
#   Description: powernv kernel advertises 16G hugepages but they can't be allocated
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

# Set or restore cmdline
function setup_cmdline(){
	local action="$1"
	local cmdline="$2"
	set -x
	local execute="grubby --"$action"=\"$cmdline\" --update-kernel=$(grubby --default-kernel)"
	eval $execute
	set +x
	if [ "${ARCH}" = "s390" ] || [ "${ARCH}" = "s390x" ]; then
		/sbin/zipl
	fi
	return $?
}

function prepare_reboot(){
	local tail_flag="$2"
	local flag=$DIR_DEBUG/$(echo $1 | awk '{ print toupper($0)}')$tail_flag
	echo $flag
	rlRun "touch $flag"
}

function check_rebooted(){
	if [ -f $DIR_DEBUG/$(echo $1 | awk '{print toupper($0)}')$2 ];then		
		return 0;
	fi
	return 1
}
# For RHEL-7.2 kernel-3.10.0-294.el7, it's a fake fix for 16g hugepage support ,Just won't give the error.
function check_16gpagesize(){
	rlAssertNotGrep "Hugepagesize:   16777216 kB"  /proc/meminfo
	if [ $? -ne 0 ];then
		m_point=$DIR_DEBUG/hugepage
		[ ! -d $m_point ] && rlRun "mkdir -p $m_point"
		rlRun "mount -t hugetlbfs none $m_point -o pagesize=16G" 
		rlRun -l "echo 1 >/proc/sys/vm/nr_hugepages"
		rlLogInfo "Current 7.2 Don't support 16g huaepage, What can we get from here?"
		local MEMINFO=/proc/meminfo
		local SYSFS_PATH=/sys/devices/system/node/node0/hugepages
		rlRun "HP_SIZE=`grep 'Hugepagesize' ${MEMINFO} | awk '{print $2}'`"
		rlRun "hp_total=`cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/nr_hugepages`"
		rlRun "hp_free=`cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/free_hugepages`"
		rlAssertEquals "NrHugepage should be 1" 1 $hp_total
		rlAssertEquals "NrHugepage should be 0" 0 $hp_free
	fi
	return $?
}

function check_sys(){
	rlIsRHEL "<6.6" && rlLogInfo "Test case is for RHEL-7" && return 1
	! cat /proc/filesystems |grep hugetlb && rlLogInfo "HugeTlbFs is not supported." && return 1

	rlRun "HugePageSize=\"$(cat /proc/meminfo |grep -i hugepagesize|awk '{print $2}')\""
	rlRun "MemTotal=$(free -g |awk 'NR==2 {print $2;}')" 0-254

	local cmppare=$(expr '$MemTotal' '>' '65')
	if [ ! "$cmppare" = 1 ];then
			rlLogInfo "Memory size is not enough for testing the case, At least 65G Mem is needed."
			#! is_in_deubg && return 1;
	fi
	return 0;
}

function is_in_deubg(){
	[ -f $DIR_DEBUG/DEBUG ]
	return $?
}

function bz1212273()
{
	check_16gpagesize
	return 
	local cmdline="default_hugepagesz=16G hugepagesz=16G hugepages=1"
	if ! check_rebooted $FUNCNAME;then
		if ! check_sys;then
			return 1;
		fi
	fi
	if check_rebooted $FUNCNAME "_SECOND";then
		rlRun "cat /proc/cmdline"
		rlLogInfo "Test has rebooted twice. cmdline should have been reset."
		return
	fi

	case $(rlGetPrimaryArch) in
		ppc64le|ppc64)
			if ! check_rebooted $FUNCNAME;then 
				setup_cmdline "args" "$cmdline"
				prepare_reboot "$FUNCNAME"
				#rlPhaseEnd 
				rhts-reboot
			else
				arg=$cmdline
				for a in $arg;do
					rlAssertGrep "$a" /proc/cmdline
				done
				check_16gpagesize
				if ! is_in_deubg;then
					setup_cmdline "remove-args" "$cmdline"
					rlLogInfo "Prepare reboots to restore the cmdline"
					prepare_reboot $FUNCNAME _SECOND
					#rlPhaseEnd
					rhts-reboot
				fi
			fi
			;;
		*)
			rlLogInfo "$(uname -m) is not intended to be tested."
			;;
	esac
}
