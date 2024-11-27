#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: kernelcore=mirror wrong memtotal detection
#   Author: Ping Fang <pifang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc. All rights reserved.
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

function kernelcore()
{
	local membase;
	if [ "$(rlGetPrimaryArch)" != "x86_64" ]; then
		rlLog "Only for x86_64"
		return
	fi

	rlRun "which numactl || return"
	rlRun "yum install -y numactl"

	nodes=$(numactl -H | grep available | cut -d ' ' -f 2)
	if [ $nodes -lt 2 ]; then
		rlLog "This test need at least 2 nodes"
		return
	fi

	rlRun "numactl -H"
	# mem size on node 1
	memsize=$(numactl -H  | awk '/node 1 size/ {print $4}')
	if [ ! -f ${DIR_DEBUG}/MEMSIZE ]; then
		echo $memsize | tee ${DIR_DEBUG}/MEMSIZE
	fi
	membase=$(cat ${DIR_DEBUG}/MEMSIZE)

	rstrnt-report-result "${FUNCNAME}-unfixed-bz2008722" SKIP

	return

	setup_cmaline_args "kernelcore=mirror" MIRROR && rlAssertGreaterOrEqual "Assert current mem size:$memsize" $membase $memsize
	cleanup_cmdline_args "kernelcore"
}
