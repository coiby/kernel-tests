#!/bin/bash

#	Copyright (c) 2018 Red Hat, Inc.
#
#	This program is free software: you can redistribute it and/or
#	modify it under the terms of the GNU General Public License as
#	published by the Free Software Foundation, either version 2 of
#	the License, or (at your option) any later version.
#
#	This program is distributed in the hope that it will be
#	useful, but WITHOUT ANY WARRANTY; without even the implied
#	warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#	PURPOSE.  See the GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# may need to set kernel options intel_iommu=on,sm_on module_blacklist=idxd
#
# Original script written by Vilem Marsik <vmarsik@redhat.com>.
# Modified by Denis Aleksandrov <daleksan@redhat.com>

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

DISTRO=$(grep DISTRO /etc/motd | cut -d= -f2)
if [ -z "$DISTRO" ]
then
	DISTRO=$(cat /etc/redhat-release)
fi

rlJournalStart

rlPhaseStartSetup
	rlRun "gcc -o memory_madvise memory_madvise.c"
rlPhaseEnd

rlPhaseStart FAIL "Functionality"
	rlLogInfo "$DISTRO"
	rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
	rlLogInfo "selinug "$(getenforce)
	rlLogInfo "CPU "$(cat /proc/cpuinfo | grep Xeon | head -1)
	rlRun "lspci -d:0cfe" 0 "IAA device presence"
	rlRun "lsmod | grep iaa" 0 "module loaded"
	rlRun "grep enabled /sys/bus/dsa/devices/iax1/state" 0 "iax1 enabled"
	rlRun "grep enabled /sys/bus/dsa/devices/iax1/wq1.0/state" 0 "wq0 enabled"
	rlRun "echo -n 'module iaa_crypto +p' > /sys/kernel/debug/dynamic_debug/control" 0 "enable iaa_crypto debug output"
	rlRun "echo -n 'module idxd +p' > /sys/kernel/debug/dynamic_debug/control" 0 "enable idxd debug output"
	rlRun "echo 0 > /sys/module/zswap/parameters/enabled" 0 "disable zswap parameters"
	rlRun "echo 50 > /sys/module/zswap/parameters/max_pool_percent" 0 "zswap max size to 50"
	rlRun "echo deflate-iaa > /sys/module/zswap/parameters/compressor" 0 "set zswap compressor to deflate-iaa"
	rlRun "echo zsmalloc > /sys/module/zswap/parameters/zpool"
	rlRun "echo 1 > /sys/module/zswap/parameters/enabled" 0 "enable zswap parameters"
	if rlIsRHEL "<10"; then
		rlRun "echo 0 > /sys/module/zswap/parameters/same_filled_pages_enabled" 0 "disable zswap same_filled_pages"
	fi
	rlRun "echo 100 > /proc/sys/vm/swappiness" 0 "swappiness to 100"
	rlRun "echo never > /sys/kernel/mm/transparent_hugepage/enabled" 0 "disable transparent hugepage"
	rlRun "echo 1 > /proc/sys/vm/overcommit_memory"

	rlRun "./memory_madvise 100" 0 "swapping 100 pages"

# ::check the following in the dmesg output::
# [root@lenovo-st650v3-01 ~]# dmesg
#[ 1218.725293] idxd 0000:79:02.0: iaa_compress: compression mode fixed, desc->src1_addr 10dfab000, desc->src1_size 4096, desc->dst_addr 120b38000, desc->max_dst_size 4096, desc->src2_addr 1152bf000, desc->src2_size 1568
#[ 1218.725307] idxd 0000:79:02.0: verify: dma_map_sg, src_addr 10dfab000, nr_sgs 1, req->src 0000000009758d36, req->slen 4096, sg_dma_len(sg) 4096
#[ 1218.725312] idxd 0000:79:02.0: verify: dma_map_sg, dst_addr 120b38000, nr_sgs 1, req->dst 000000000583fe54, req->dlen 228, sg_dma_len(sg) 8192
#[ 1218.725317] idxd 0000:79:02.0: (verify) compression mode fixed, desc->src1_addr 120b38000, desc->src1_size 228, desc->dst_addr 10dfab000, desc->max_dst_size 4096, desc->src2_addr 0, desc->src2_size 0

rlPhaseEnd

rlPhaseStartCleanup
# ::roll back, disable zswap::
	rlRun "echo lzo > /sys/module/zswap/parameters/compressor"
	rlRun "swapoff -a"
	rlRun "echo 0 > /sys/module/zswap/parameters/accept_threshold_percent"
	rlRun "echo 0 > /sys/module/zswap/parameters/max_pool_percent"
	rlRun "echo 0 > /sys/module/zswap/parameters/enabled"
	rlRun "swapon -a"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
