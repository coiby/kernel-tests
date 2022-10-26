#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: 
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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

# Turn off the hardened_us, and it should not panic kernel
function out_of_boundary()
{
	pushd $DIR_SOURCE/hardened_usercopy
	local flag=""
	rlIsRHEL ">=8" && flag="EXTRA_CFLAGS=-DRHEL8"
	rlRun "make $flag"
	rlRun "insmod usercopy.ko"
	rlRun "rmmod usercopy"
	popd
}

# Default value is on
function hardened_usercopy()
{
	local support=$(grep CONFIG_HARDENED_USERCOPY=y /boot/config-$(uname -r))
	uname -r | grep x86_64 || return
	# This can corruption kernel memory, and leading to system oops. Not good for reguler run.
	return
	[ -z "$support" ] && rlLog "debug_guardpage_minorder is not supported." && return 0
	setup_cmdline_args "hardened_usercopy=off" HARDENED_USERCOPY_OFF && out_of_boundary
	cleanup_cmdline_args "hardened_usercopy=off"
	return 0
}
