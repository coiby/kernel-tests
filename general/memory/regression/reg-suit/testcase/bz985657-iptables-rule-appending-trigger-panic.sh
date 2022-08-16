#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Shizhao Chen <shichen@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc. All rights reserved.
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
. /usr/bin/rhts-environment.sh
. /usr/share/beakerlib/beakerlib.sh

function iptables_append()
{
    (( start = $1 * 10000 + 1))
    (( end = start + 10000 ))

    chain="chain_$1"

    iptables -N $chain

    for port in $(seq $start $end); do
        iptables -I $chain -s 192.168.102.103 -p udp --sport $port -j ACCEPT
        if [ $(( port % 1000 )) -eq 0 ]; then
            echo "$((port-10000))th rule appended in ${chain}."
        fi
    done
}

function bz985657()
{
    rlRun "iptables_append 1"
    rlRun "iptables_append 2"
    rlRun "iptables_append 3"

    iptables -F
    iptables --delete-chain
}
