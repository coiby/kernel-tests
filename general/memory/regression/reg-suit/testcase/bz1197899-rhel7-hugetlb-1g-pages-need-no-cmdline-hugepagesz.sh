#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1197899
#   Description: kernel: ASLR randomization hardening for AMD F15h processors
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

function bz1197899()
{
    if rlIsRHEL ">=7.2";then
	    case $(rlGetPrimaryArch) in
		x86_64)
			rlRun "CpuVendor=$(lscpu |grep -m 1 "Vendor ID" |awk -F ':'  '{print $2}'|sed 's/ //g')"
			rlRun "CpuFamily=$(lscpu |grep -m 1 "CPU family" |awk -F ':' '{print $2}'|sed 's/ //g')"
			rlRun "Model=\"$(lscpu |grep -m 1 "Model" |awk -F ':' '{print $2}'|sed 's/ //g')\""
			rlRun "NumaNode=$(lscpu |grep -m 1 "NUMA node" |awk -F ':' '{print $2}'|sed 's/ //g')"

			rlRun -l "cat /proc/cpuinfo|grep -m 1 flags" 0-254
			rlRun -l "cat /proc/cpuinfo|grep -m 1 flags|grep pdpe1gb" 0-254
			[ $? -ne 0 ] && rlLogWarning "${FUCNAME}: pdpe1g flag is not supported by current CPU." && return

			rlAssertNotGrep "hugepage" /proc/cmdline "-i"
			[ $? -ne 0 ] && rlLogInfo "To verify this featrue, please remove *any* hugepage configure in kernel cmdline." && return

			local i
		        for ((i = 0; i < NumaNode; i++)); do
		             rlAssertExists "/sys/devices/system/node/node${i}/hugepages/hugepages-1048576kB"
			done
		    ;;
		*)
			rlLogInfo "$(uname -m) is not intended to be tested."
		    ;;
	    esac
    else
	rlLogWarning "The default 1g huapage pool support is added from RHEL-7.2 kernel-3.10.0-239.el7"
    fi
}
