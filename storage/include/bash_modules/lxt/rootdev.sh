#!/bin/bash
# Copyright (c) 2006 Red Hat, Inc. All rights reserved. This copyrighted
# material is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
# USA.
#
# Author: Xiaowei Li   <xiaoli@redhat.com>

test "$LXT_ROOTDEV" = 1 || return
LXT_ROOTDEV=1

source /mnt/tests/kernel/storage/include/bash_modules/lxt/tc.sh

#
# get the root disk of /
# usage: rootdisk=$(get_root_disk)
# always return 0
get_root_disk ()
{
    # get the root device
    # some times it's uuid style in fstab, so we cannot use fstab to check
    # the root device
    # rootdev=$(cat /etc/fstab  | grep -w / | awk '{print $1}')
    rootdev=$(mount | grep -w / | awk '{print $1}')

    # if it's the dm node, lv, mdadm raid..
    # if it's symbolic link, get the source file
    while test -L "$rootdev"
    do
        origin_rootdev=$(readlink "$rootdev")
        if echo "$origin_rootdev" | grep '^/'
        then
           rootdev=$origin_rootdev 
        else
           dir=$(dirname "$rootdev")
           rootdev="$dir/$origin_rootdev"    
        fi
    done

    devname=$(basename "$rootdev")

    # only support the lvm pv or raid on a single device
    # get the root disk, maybe has multiple slaves if it's the
    # multipathed disk
    # /sys/block/dm-3/slaves/dm-2/slaves/dm-0/slaves/sda/...
    while ls /sys/block/"$devname"/slaves/* &>/dev/null
    do
        devname=$(ls /sys/block/"$devname"/slaves/ | head -n 1)
    done

    # if it's a partition
    # /sys/block/vda/vda2...
    if test -d /sys/block/"$devname"
    then
        echo "$devname"
    else
        devname=$(echo "$devname" | sed 's/[0-9]$//g')
        test -d /sys/block/"$devname" && echo "$devname"
    fi
}
