#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Yaoyao Ma <yaoma@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc. All rights reserved.
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
#   Software Foundation, Inc., 51 Franklin street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function bz1447952()
{
	krev=$(uname -r | cut -d'-' -f 2 | cut -d'.' -f 1)
	behavior="old"
	echo krev=$krev

	if [ $(rlGetDistroRelease) -eq 8 ] && [ $krev -gt 265 ] || rlIsRHEL ">=9" || rlIsFedora; then
		behavior="new"
	fi

	# 8.5 use old behavior again
	if [ $(rlGetDistroRelease) -eq 8 ] && [ $krev -gt 305 ]; then
		behavior="old"
	fi

	# 9.0 5.14 use old behavior
	if [ $(rlGetDistroRelease) -eq 9 ] && [ $krev -ge 1 ]; then
		behavior="old"
	fi

	if [ "$behavior" = old ]; then
		echo "Using behavior=old, remote memory accesss fault don't change memory accounting of faultee"
	else
		echo "Using behavior=new, remote memory accesss fault does change memory accounting of faultee"
	fi


	case $(rlGetPrimaryArch) in
		i386|i686)
			mark_skip "bz1447952" "skip bz1447952 in i386 i686"
			return
			;;
		*)
			rlLogInfo "bz1447952 to be tested."
			;;
	esac

	if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
		rlLogWarning "Can't build test binary"
		return
	fi

	rlRun "./$FUNCNAME > /tmp/$FUNCNAME.log"

	str_1=$(cat /tmp/$FUNCNAME.log  | grep "^Size:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log  | grep "^Size:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "Size Error"
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Rss:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Rss:" | tail -1)
	val_1=$(echo $str_1 | awk '{print $2}')
	val_2=$(echo $str_2 | awk '{print $2}')

	if [ $behavior == "old" ]; then
		if [ "$str_1" != "$str_2" ]; then
			rlFail "Rss Error"
		fi
	else
		if [ $(($val_1+4096)) != $val_2 ]; then
			rlFail "Rss Error"
		fi
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Pss:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Pss:" | tail -1)
	val_1=$(echo $str_1 | awk '{print $2}')
	val_2=$(echo $str_2 | awk '{print $2}')

	if [ $behavior == "old" ]; then
		if [ "$str_1" != "$str_2" ]; then
			rlFail "Pss Error"
		fi
	else
		if [ $(($val_1+4096)) != $val_2 ]; then
			rlFail "Pss Error"
		fi
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Shared_Clean:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Shared_Clean:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "Shared_Clean Error"
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Shared_Dirty:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Shared_Dirty:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "Shared_Dirty Error"
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Private_Clean:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Private_Clean:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "Private_Clean Error"
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Private_Dirty:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Private_Dirty:" | tail -1)
	val_1=$(echo $str_1 | awk '{print $2}')
	val_2=$(echo $str_2 | awk '{print $2}')

	if [ $behavior == "old" ]; then
		if [ "$str_1" != "$str_2" ]; then
			rlFail "Private_Dirty Error"
		fi
	else
		if [ $(($val_1+4096)) != $val_2 ]; then
			rlFail "Private_Dirty Error"
		fi
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Referenced:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Referenced:" | tail -1)
	val_1=$(echo $str_1 | awk '{print $2}')
	val_2=$(echo $str_2 | awk '{print $2}')

	if [ $behavior == "old" ]; then
		if [ "$str_1" != "$str_2" ]; then
			rlFail "Referenced Error"
		fi
	else
		if [ $(($val_1+4096)) != $val_2 ]; then
			rlFail "Referenced Error"
		fi
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Anonymous:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Anonymous:" | tail -1)
	val_1=$(echo $str_1 | awk '{print $2}')
	val_2=$(echo $str_2 | awk '{print $2}')

	if [ $behavior == "old" ]; then
		if [ "$str_1" != "$str_2" ]; then
			rlFail "Anonymous Error"
		fi
	else
		if [ $(($val_1+4096)) != $val_2 ]; then
			rlFail "Anonymous Error"
		fi
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Swap:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Swap:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "Swap Error"
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^KernelPageSize:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^KernelPageSize:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "KernelPageSize Error"
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^MMUPageSize:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^MMUPageSize:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "MMUPageSize Error"
	fi

	str_1=$(cat /tmp/$FUNCNAME.log | grep "^Locked:" | head -1)
	str_2=$(cat /tmp/$FUNCNAME.log | grep "^Locked:" | tail -1)

	if [ "$str_1" != "$str_2" ]; then
		rlFail "Locked Error"
	fi

	rlRun "rm -rf /tmp/$FUNCNAME.log"
}
