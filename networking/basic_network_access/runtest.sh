#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Test will check if the board can access the network through 2 tests.
#   1. Will check if there are dns servers configured and test connectivity to them.
#   2. will check access to external dns servers
#   Author: Michael Menasherov <mmenashe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 3.
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
# Include the BeakerLib environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

declare -a DNS_EXTERNAL=("8.8.8.8" "1.1.1.1" "208.67.222.222")

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
    rlPhaseEnd

    rlPhaseStartTest "Check if dns servers are configured and accessible on the board"
        mapfile -t dns_ipv4 < <(nmcli dev show | grep -m2 'IP4.DNS' | awk '{print $2}')
        if [ "${#dns_ipv4[@]}" -gt 0 ]; then
            for i in "${dns_ipv4[@]}"; do
                rlLog "Pinging $i"
                rlRun "ping -c3 $i" 0 "Pinging $i"
            done
        else
            rlLogWarning "No dns servers are configured on the board,if intended please ignore."
        fi
    rlPhaseEnd

    rlPhaseStartTest "Check if can access external dns servers"
        for i in "${DNS_EXTERNAL[@]}"; do
            rlLog "Pinging $i"
            rlRun "ping -c3 $i" 0 "Pinging $i"
        done
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
