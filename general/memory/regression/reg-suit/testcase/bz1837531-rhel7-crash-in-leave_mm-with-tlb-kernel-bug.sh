#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1837531
#   Description: The kernel crashes in leave_mm() with a message "kernel BUG at arch/x86/mm/tlb.c:48!"
#   Author: Ping Fang <pifang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc. All rights reserved.
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

function bz1837531()
{
	if [ ! -d /sys/firmware/efi/ ]; then
		rlLog "skip"
		return 0
	fi
	rlRun "mkdir /tmp/efivars"
	rlRun "mount -t efivarfs none /tmp/efivars/"
	rlRun "dd if=/dev/zero of=/tmp/tempfile bs=1 count=8192 > /dev/null 2>&1"
	rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"
	rlRun "./$FUNCNAME"
	rlRun "umount /tmp/efivars"
	rlRun "rm -rf /tmp/efivars"
}
