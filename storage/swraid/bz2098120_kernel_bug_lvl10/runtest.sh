#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc. All rights reserved.
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

FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)

source ../../../cki_lib/libcki.sh || exit 1
source  "$CDIR"/../../../cki_lib/libcki.sh || exit 1

function runtest()
{
rlRun "mdadm -Ss"
rlRun "mdadm --create --run /dev/md0 --level 0  --metadata 1.2 \
--raid-devices 3 /dev/loop[0-2] --chunk 512 "

if [ $? -ne 0 ];then
rlFail "FAIL: Failed to create md raid $RETURN_STR"
exit
fi

rlLog "INFO: Successfully created md raid $RETURN_STR"

rlLog "mkfs -t ext4 /dev/md0"
mkfs -t ext4 /dev/md0

rlRun "mkdir -p /mnt/md_test"
rlRun "mount -t ext4 /dev/md0 /mnt/md_test"
rlRun "umount /mnt/md_test"

rlRun "mdadm --grow /dev/md0 -l10 -a /dev/loop3 /dev/loop4 /dev/loop5 --backup-file=tmp0"

return $CKI_PASS
}

function startup
{
if ( ! rpm -q mdadm );then
yum -y install mdadm
fi

for i in {0..5};do
rlRun "dd if=/dev/urandom of=/opt/loop_$i bs=4M count=500"
rlRun "losetup /dev/loop$i /opt/loop_$i"
done

return $CKI_PASS
}


function cleanup
{
rlRun "mdadm --stop /dev/md0"
rlRun "losetup -D"
rlRun "rm -f /opt/loop_*"
return $CKI_PASS
}


cki_main
exit $?

