#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1240883
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

function bz1240883()
{
	case $(rlGetPrimaryArch) in
		x86_64)
			rlRun "CpuVendor=$(lscpu |grep -m 1 "Vendor ID" |awk -F ':'  '{print $2}'|sed 's/ //g')"
			rlRun "CpuFamily=$(lscpu |grep -m 1 "CPU family" |awk -F ':' '{print $2}'|sed 's/ //g')"
			rlRun "Model=\"$(lscpu |grep -m 1 "Model" |awk -F ':' '{print $2}'|sed 's/ //g')\""
			rlRun "origin=$(sysctl kernel.randomize_va_space|sed 's/ //g')"
			rlRun -l "sysctl kernel.randomize_va_space=2"
			rlLogInfo "self mem space display."
			rlRun -l 'for i in `seq 1 10`; do cat /proc/self/maps | grep "r-xp.*libc" ; done'

			rlLogInfo "vdso section check"
			rlRun -l 'for i in `seq 1 10`; do cat /proc/self/maps | grep vdso ; done'
			rlRun -l 'for i in `seq 1 10`; do cat /proc/self/maps | grep vdso|grep "[^08]000-";done|wc -l |tee vdso-map' 0-255

			rlLogInfo "vvar section check"
			if cat /proc/self/maps |grep vvar;then
				rlRun -l 'for i in `seq 1 1000`; do cat /proc/self/maps |grep vvar |grep "[^08]000-";done |wc -l|tee vvar-map' 0-255
			else
				rlLogWarning "There is no vvar section in self mem space mapped."
			fi

			rlLogInfo "- stack section check"
			rlRun -l 'for i in `seq 1 10`; do cat /proc/self/maps | grep stack|grep "[^08]000-"; done|wc -l|tee stack-map' 0-254
			# evaluate the result.
			rlAssertNotGrep "0" vdso-map "-w"
			rlAssertNotGrep "0" stack-map "-w"
			[ -f vvar-map ] && rlAssertNotGrep "0" vvar-map "-w"
			eval sysctl $origin
			;;
		*)
			rlLogInfo "$(uname -m) is not intended to be tested."
			;;
	esac
}
