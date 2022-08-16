#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   FIXMEHERE
#   Description:
#   Author: Chao Ye <cye@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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

function bz647849()
{
    if ! grep -q hugetlbfs /proc/filesystems; then
        rlLog "hugetlbfs not enabled"
        return
    fi

    if rlIsRHEL ">6"; then
        major=$(source /etc/os-release; echo $VERSION_ID | cut -d. -f1)
        url=https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm

        if ! curl --head -s -f $url -o /dev/null; then
            report_result "bz647849" SKIP
            return
        fi
        yum install -y $url
    fi

    rlRun "yum install -y ntfsprogs ntfs-3g" 0-255
    if ! rpm -q ntfsprogs; then
	rlLogWarning "There is no ntfsprogs package available. Break test."
	local epelrpm=$(rpm -qa | grep 'epel-release')
	rpm -e $epelrpm
	yum clean all
        return 1;
    fi
    rlRun "swapoff -a"
    local device=$(grep swap /etc/fstab | awk '{print $1}')
    rlRun "mkfs.ntfs $device"
    rlRun "mkdir /$FUNCNAME"
    rlRun "mount.ntfs $device /$FUNCNAME"
    local bs=$(stat -c %s -f /$FUNCNAME)
    local nr=$(echo $(stat -c %a -f /$FUNCNAME) / 2 - 1 | bc)
    rlRun "dd if=/dev/zero of=/$FUNCNAME/ReadFile bs=$bs count=$nr"
    for i in `seq 100`; do
        dd if=/dev/zero of=/$FUNCNAME/WriteFile bs=$bs count=$nr
    done &
    local loops="$!"
    for i in `seq 1000`; do
        dd if=/$FUNCNAME/ReadFile of=/dev/null bs=$bs count=$nr
    done &
    loops+=" $!"

    # set a timelimit. As for reg-suit, this case will cause watchdog exceed
    #    to be killed, and leave swap unmounted. Consider to extend in Tier2
    sleep ${WAITTIME:-300}
    kill $loops
    pkill dd
    rlRun "umount /$FUNCNAME"
    rlRun "rm -rf /$FUNCNAME"
    rlRun "mkswap $device"
    rlRun "swapon -a"
    rlLog "Test PASS"
    rlRun "yum-config-manager --disable epel" 0-254 "Disable the epel repo for the yum cache is not always enough."
    rpm -e epel-release-latest
    yum clean all
}
