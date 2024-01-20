#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
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

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

function install_kernel_devel
{
    local kver=$(uname -r)
    echo $kver | grep -q 'debug'
    if [ $? == 0 ]; then
        yum install -y kernel-debug-devel
    else
        yum install -y kernel-devel
    fi
}

rlJournalStart
    rlPhaseStartSetup
        install_kernel_devel
        unset ARCH
        rlRun "make module"
    rlPhaseEnd

    rlPhaseStartTest Test
        rmmod drain_pages
        rlRun "insmod ./drain_pages.ko"
    rlPhaseEnd

    rlPhaseStartCleanup
        # do not cleanup, the drain_pages runs in the
        # background to make memory fragmented.
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText

