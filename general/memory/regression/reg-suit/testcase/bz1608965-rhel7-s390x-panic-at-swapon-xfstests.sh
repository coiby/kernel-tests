#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: panic at swapon with empty or holey swapfile on pmem
#   Author: Ping Fang <pifang@redhat.com>
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
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function bz1608965()
{
	rlRun "yum install xfsprogs"

	# build pmem
	if [[ ! -e $DIR_DEBUG/$FUNCNAME.rebootflag_f && "$(uname -m)" == "x86_64" ]]; then
		rlLog "first reboot"
		rlRun "grubby --args 'memmap=128M\!4G' --update-kernel DEFAULT"
		touch $DIR_DEBUG/$FUNCNAME.rebootflag_f
		rhts-reboot
	fi

	if [[ ! -e $DIR_DEBUG/$FUNCNAME.rebootflag_s ]]; then

		rlLog "first reboot done"
		
		rlRun "gcc $DIR_SOURCE/mkswap.c -o mkswap"
		rlRun "gcc $DIR_SOURCE/swapon.c -o swapon"
		TMP=$(mktemp -d -p.)

		if [[ "$(uname -m)" == "x86_64" ]] ; then
			rlLog "mount pmem"
			mkfs -t xfs /dev/pmem0
			mount /dev/pmem0 $TMP/
		fi

		touch $TMP/swapfile

		touch $DIR_DEBUG/$FUNCNAME.rebootflag_s

		rlLog "start swapon empty file"

		xfs_io -f -c "truncate 40960" $TMP/swapfile

		./mkswap $TMP/swapfile
		./swapon $TMP/swapfile

		rm -f $TMP/swapfile && touch $TMP/swapfile

		rlLog "start swapon holey file"

		xfs_io -f -c "pwrite -S 0x61 0 4096" $TMP/swapfile

		./mkswap $TMP/swapfile
		./swapon $TMP/swapfile


		if [[ "$(uname -m)" == "x86_64" ]] ; then
			rlLog "secend reboot"
			rlRun "grubby --remove-args 'memmap' --update-kernel DEFAULT"
			rhts-reboot
		fi
	fi

}

function casecleanup()
{
	if [[ "$(uname -m)" == "x86_64" ]] ; then
		rlLog "clean kernel parameter"
		rlRun "grubby --remove-args 'memmap' --update-kernel DEFAULT"
		rhts-reboot
	fi
}
