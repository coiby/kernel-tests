#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
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

#  This case used to verify early cpu trace ring buffer allocation panic.
#  RHEL7,8 enable CONFIG_DEFERRED_STRUCT_PAGE_INIT on x86_64, which defer the early
#  page initialization during early boot. But trace ring buffer allocation
#  callback registered on cpuhp chain, invoked during smp_init() before
#  page_alloc_init_late(). Then crash the system. bz1496330

function trace_buf_size()
{
	#get early avaliable memory from kernel log. beaker will clean dmesg, so use journalctl.
	#rhel6 not backport this regression. only check on rhel7,8 x86_64 which have journalctl.

	if rlIsRHEL 6; then
		rlLog "Only for rhel > 6"
		rstrnt-report-result "${FUNCNAME[0]}-is_rhel6" SKIP
		return 0
	fi
	if [ "$(rlGetPrimaryArch)" != "x86_64" ]; then
		rlLog "Only for x86_64"
		rstrnt-report-result "${FUNCNAME[0]}-not_x86_64" SKIP
		return 0
	fi

	cpus=$(grep -w processor /proc/cpuinfo | wc -l)
	early_mem_K=$(journalctl -kb | awk -e '/Memory:/ {split(toupper($7), array, "K"); print array[1]}')
	dmi_total_mem=$(dmidecode -t 17 | grep -e 'Form Factor: DIMM' -B1 --no-group-separator | awk -e '/[[:digit:]]/ {sum+=$2; unit=$3} END{print sum" "unit}')
	total_mem=$(echo $dmi_total_mem | awk -e '{if ($2 == "MB") print $1/1024; else print $1}')
	mem_early_B=$(($early_mem_K * 1024))

	if  [ $total_mem -lt $cpus ]; then
		rlLog "total_mem $total_mem < cpus $cpus"
		rstrnt-report-result "${FUNCNAME[0]}-total_mem" SKIP
		return 0
	fi
	per_core_buf=$(($mem_early_B/$cpus))

	if [ $per_core_buf -gt 1048576 ]; then
		per_core_buf=1048576
	fi

	setup_cmdline_args "trace_buf_size=$per_core_buf trace_event=sched:*" trace_buf
	sleep 60
	cleanup_cmdline_args "trace_buf_size trace_event" trace_buf
	return 0
}
