#!/bin/bash
#
# Copyright (c) 2022 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)

source ../../../cki_lib/libcki.sh || exit 1


function runtest
{
# Refer to bugzilla: https://bugzilla.redhat.com/show_bug.cgi?id=2066373 
   cki_run "mdadm --create --run /dev/md0 --level 0  --metadata 1.2 \
       --raid-devices 3 /dev/loop0 /dev/loop1 /dev/loop2 --chunk 512"
   cki_run "mdadm --grow -l10 /dev/md0 \
       -a  /dev/loop3 /dev/loop4 /dev/loop5 --backup-file=tmp0"

    return $CKI_PASS
}

function startup
{
    for i in {0..8};do 
        cki_run "dd if=/dev/urandom of=/opt/loop_$i bs=1M count=500"
    done

    for i in {0..8};do 
        cki_run "losetup /dev/loop$i /opt/loop_$i"
    done

    return $CKI_PASS
}

function cleanup
{
    cki_run "mdadm --stop /dev/md0"
    cki_run "losetup -D"
    cki_run "rm -f /opt/loop_*"
    return $CKI_PASS
}

cki_main
exit $?
