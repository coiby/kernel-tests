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

source  "$CDIR"/../../../cki_lib/libcki.sh || exit 1

function runtest()
{
rlRun "mdadm --create --run /dev/md0 --level 0  --metadata 1.2 \
--raid-devices 2 /dev/loop0 /dev/loop1"
if [ $? -ne 0 ];then
rlFail "FAIL: Failed to create md raid level0"
exit
fi

rlLog "INFO: Successfully created md raid level0"

layout=$(mdadm -D /dev/md0 | grep 'Layout' | awk '{print $3}')
if [[ "$layout" == "-unknown-" ]];then
rlFail "FAIL: RAID 0 default layout is -unknown- "
cleanup
exit 1
fi

MD_Clean_RAID /dev/md0
return $CKI_PASS

}


function startup
{
if ( ! rpm -q mdadm );then
yum -y install mdadm
fi

for i in {0..2};do
rlRun "dd if=/dev/urandom of=/opt/loop_$i bs=1M count=500"
done

for i in {0..2};do
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

