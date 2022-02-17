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

. ../../../cki_lib/libcki.sh || exit 1

# Include networking common helpers.
FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
NET_COMMON_ROOT="${CDIR%/networking/vrf/*}/networking/common"

TEST="networking/vrf/sanity_checks"

# Test doesn't work w/o IPv6.
if grep "ipv6.disable=1" /proc/cmdline ; then
	echo "Skip test as system doesn't have IPv6."
	rstrnt-report-result $TEST SKIP
	exit
fi

# Load VRF module
lsmod | grep vrf || modprobe vrf

bash $NET_COMMON_ROOT/tools/netns_clean.sh
ns="ns1 ns2 ns3"

setup() {
    for n in $ns; do
        rlRun "ip netns add $n"
    done
    rlRun "ip -net ns1 link add vrf0-ns1 type vrf table 10"
    rlRun "ip -net ns1 link add vrf1-ns1 type vrf table 20"
    rlRun "ip link add veth12 netns ns1 type veth peer name veth21 netns ns2"
    rlRun "ip link add veth13 netns ns1 type veth peer name veth31 netns ns3"
    rlRun "ip -net ns1 link set veth12 up"
    rlRun "ip -net ns1 link set veth13 up"
    rlRun "ip -net ns1 link set vrf0-ns1 up"
    rlRun "ip -net ns1 link set vrf1-ns1 up"
    rlRun "ip -net ns2 link set veth21 up"
    rlRun "ip -net ns3 link set veth31 up"
    rlRun "ip -net ns1 link set master vrf0-ns1 veth12"
    rlRun "ip -net ns1 link set master vrf1-ns1 veth13"
}

cleanup() {
    for n in $ns; do
        rlRun "ip netns pids $n | xargs -r kill"
        rlRun "ip netns del $n"
    done
}

# Test adding duplicate addresses to different VRFs. Keep the setup after the
# test to reuse the addresses in following tests.
duplicate_addrs() {
    rlRun "ip -net ns1 addr add 10.0.42.1/24 dev veth12"
    rlRun "ip -net ns2 addr add 10.0.42.2/24 dev veth21"
    rlRun "ip -net ns1 addr add 1111:1::1/64 dev veth12"
    rlRun "ip -net ns2 addr add 1111:1::2/64 dev veth21"
    rlRun "ip -net ns1 addr add 10.0.42.1/24 dev veth13"
    rlRun "ip -net ns3 addr add 10.0.42.2/24 dev veth31"
    rlRun "ip -net ns1 addr add 1111:1::1/64 dev veth13"
    rlRun "ip -net ns3 addr add 1111:1::2/64 dev veth31"
}

# Sanity tests, pinging addresses defined in both VRFs, and checking only the
# right one sees packets.
sanity() {
    rlRun "ip netns exec ns1 ip vrf exec vrf0-ns1 tcpdump -i any -w vrf0.pcap &"
    rlRun "ip netns exec ns1 ip vrf exec vrf1-ns1 tcpdump -i any -w vrf1.pcap &"
    rlRun "sleep 5"
    rlRun "ip netns exec ns2 ping -c3 10.0.42.1"
    rlRun "ip netns exec ns3 ping -c3 1111:1::1"
    rlRun "pkill tcpdump"
    rlRun "sleep 5"

    rlRun "tcpdump -r vrf0.pcap -nnle | grep 10.0.42.2"
    [ $? -ne 0 ] && rlRun -l "tcpdump -r vrf0.pcap -nnle"
    rlRun "tcpdump -r vrf1.pcap -nnle | grep -qv 10.0.42.2"
    [ $? -ne 0 ] && rlRun -l "tcpdump -r vrf1.pcap -nnle"

    rlRun "tcpdump -r vrf1.pcap -nnle | grep 1111:1::1"
    [ $? -ne 0 ] && rlRun -l "tcpdump -r vrf1.pcap -nnle"
    rlRun "tcpdump -r vrf0.pcap -nnle | grep -qv 1111:1::1"
    [ $? -ne 0 ] && rlRun -l "tcpdump -r vrf0.pcap -nnle"

    rlRun "rm vrf0.pcap vrf1.pcap"
}

# Check routes information in and out the VRFs.
routes() {
    rlRun "ip -net ns1 route get 10.0.42.1 vrf vrf0-ns1"
    rlRun "ip -net ns1 route get 10.0.42.1 vrf vrf1-ns1"
    rlRun "ip -net ns1 route get 10.0.42.1" "1-255"

    rlRun "ip -net ns1 route get 1111:1::1 vrf vrf0-ns1"
    rlRun "ip -net ns1 route get 1111:1::1 vrf vrf1-ns1"
    rlRun "ip -net ns1 route get 1111:1::1" "1-255"
}

# Some checks playing with rules, and checking the route information is
# correctly handled depending on the rules order.
rules() {
    rlRun "ip -net ns1 addr add 127.0.0.1/8 dev lo"
    rlRun "ip -net ns1 addr add 127.0.0.1/8 dev vrf0-ns1"

    rlRun "ip -net ns1 route get 127.0.0.1 | grep 'dev lo'"
    rlRun "ip -net ns1 route get 127.0.0.1 vrf vrf0-ns1 | grep 'dev lo'"
    rlRun "ip -net ns1 route get 127.0.0.1 vrf vrf1-ns1 | grep 'dev lo'"

    rlRun "ip -net ns1 rule del pref 0"
    rlRun "ip -net ns1 rule add pref 2000 table local"

    rlRun "ip -net ns1 route get 127.0.0.1 | grep 'dev lo'"
    rlRun "ip -net ns1 route get 127.0.0.1 vrf vrf0-ns1 | grep 'dev vrf0-ns1'"
    rlRun "ip -net ns1 route get 127.0.0.1 vrf vrf1-ns1 | grep 'dev lo'"

    rlRun "ip -net ns1 rule del pref 2000"
    rlRun "ip -net ns1 rule add pref 0 table local"

    rlRun "ip -net ns1 addr del 127.0.0.1/8 dev lo"
    rlRun "ip -net ns1 addr del 127.0.0.1/8 dev vrf0-ns1"
}

# Basic sanity checks for multicast handling in VRFs.
multicast() {
    rlRun "ip netns exec ns1 sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0"
    rlRun "ip netns exec ns2 sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0"

    rlRun "ip netns exec ns1 ip vrf exec vrf0-ns1 ping -c3 -I veth12 224.0.0.1"
    rlRun "ip netns exec ns2 ping -c3 -I veth21 224.0.0.1"
    rlRun "ip netns exec ns1 ip vrf exec vrf0-ns1 ping -c3 -I veth12 ff02::1"
    rlRun "ip netns exec ns2 ping -c3 -I veth21 ff02::1"

    rlRun "ip netns exec ns1 sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1"
    rlRun "ip netns exec ns2 sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1"
}

rlJournalStart
    rlPhaseStartSetup
        setup
    rlPhaseEnd

    rlPhaseStartTest "Duplicate addrs"
        duplicate_addrs
    rlPhaseEnd

    rlPhaseStartTest "Sanity checks"
        sanity
    rlPhaseEnd

    rlPhaseStartTest "Routes"
        routes
    rlPhaseEnd

    rlPhaseStartTest "Multicast"
        multicast
    rlPhaseEnd

    rlPhaseStartCleanup
        cleanup
    rlPhaseEnd

    rlJournalPrintText
rlJournalEnd
