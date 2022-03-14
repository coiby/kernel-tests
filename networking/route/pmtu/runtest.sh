#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of kernel/networking/route/mr
#   Description:  Multicast routing testing
#   Author: Jianlin Shi<jishi@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. ../../../cki_lib/libcki.sh || exit 1
. ./common/include.sh || exit 1
. ./common/network.sh || exit 1
. ./common/service.sh || exit 1
. ./common/install.sh || exit 1

export TEST="networking/route/pmtu"
YUM=$(cki_get_yum_tool)

# Test doesn't run without IPv6
if grep "ipv6.disable=1" /proc/cmdline ; then
    rlLog "Skip test as system doesn't have IPv6."
    rstrnt-report-result $TEST SKIP
    exit
fi

# Functions



# Parameters
TEST_TYPE=${TEST_TYPE:-"netns"}
TEST_TOPO=${TEST_TOPO:-"default"}
SEC_TYPE=${SEC_TYPE:-"nosec ipsec"}
TESTMASK="yes"

. ./include.sh || exit 1


TEST_ITEMS=${TEST_ITEMS:-$TEST_ITEMS_ALL}
rlJournalStart

rlPhaseStartSetup

    rlRun "lsmod | grep sctp || modprobe sctp" "0-255"



    rlLog "items include:$TEST_ITEMS"
rlPhaseEnd

for DO_SEC in $SEC_TYPE
do
    netns_clean.sh
    pmtu_test
    netns_clean.sh
done

rlJournalEnd
