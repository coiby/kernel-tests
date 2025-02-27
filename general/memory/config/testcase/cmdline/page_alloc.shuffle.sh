#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: excercise page allocator shuffle to sanity check
#   Author: Chunyu Hu <chuhu@redhat.com>
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


function page_alloc_shuffle()
{
	rlRun "grep Y /sys/module/page_alloc/parameters/shuffle"

	uname -r | grep x86_64 || { rstrnt-report-result ${FUNCNAME[0]} SKIP; return; }

	dmesg -C
	pushd $DIR_SOURCE/shuffle_pages
	if rlIsRHEL 10; then
		patch -p2 < rhel10_shuffle_compile_fix.patch
	fi
	rlRun "make"
	rlRun "insmod shuffle_pages.ko"
	sleep 10
	rlRun "rmmod shuffle_pages.ko"
	rlRun "dmesg | grep PASS"  0
	popd

	return
}

function page_alloc.shuffle()
{
	if ! grep CONFIG_SHUFFLE_PAGE_ALLOCATOR=y /boot/config-$(uname -r); then
		rlLog "page_allocator shuffle is not supported in this kernel, please check kernel config. skip."
		rstrnt-report-result  "${FUNCNAME[0]}" SKIP
		return 0
	fi

	setup_cmdline_args "page_alloc.shuffle=1" PAGE_ALLOC_SHUFFLE && page_alloc_shuffle
	cleanup_cmdline_args "page_alloc.shuffle"

	return 0
}
