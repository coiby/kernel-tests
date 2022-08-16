#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   fio with ioengine=pmemblk on fsdax failed.
#   Description:
#   Author: Ping Fang <pifang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

function bz1739889()
{
	if ! lsmod | grep libnvdimm; then
		return
	fi
	rpm -q ndctl || yum install -y ndctl
	rpm -q fio || yum install -y fio 
	ndctl destroy-namespace all -r all -f
	ndctl create-namespace -r region0 -m fsdax -s 12G
	mkfs.xfs -f /dev/pmem0
	mkdir /mnt/dax_device_add
	mount -o dax,noatime /dev/pmem0 /mnt/dax_device_add
	wget --no-check-certificate https://gitlab.cee.redhat.com/kernel-qe/kernel/raw/master/storage/NVDIMM/fsdax_device_add/pmemblk.fio
	fio pmemblk.fio
}

