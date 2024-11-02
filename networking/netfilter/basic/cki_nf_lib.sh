#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#    Copyright (c) 2014 Red Hat, Inc. All rights reserved.
#
#    This copyrighted material is made available to anyone wishing
#    to use, modify, copy, or redistribute it subject to the terms
#    and conditions of the GNU General Public License version 2.
#
#    This program is distributed in the hope that it will be
#    useful, but WITHOUT ANY WARRANTY; without even the implied
#    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#    PURPOSE. See the GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public
#    License along with this program; if not, write to the Free
#    Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#    Boston, MA 02110-1301, USA.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || . /usr/lib/beakerlib/beakerlib.sh || exit 1
. ${PWD%%networking*}/kernel-include/runtest.sh || exit 1

#--------------------------
#Put Required packages here
#--------------------------
for pkg in nmap-ncat lksctp-tools tcpdump conntrack-tools nftables ipset iptables
do
	dnf -y install $pkg
done

if uname -r | grep -q "\.el10"; then
	dnf -y install "$(K_GetRunningKernelRpmSubPackageNVR modules-extra)"
fi

4or6()
{
	if [[ $1 =~ .*:.* ]];then
	    echo "6"
	else
	    echo "4"
	fi
}

netfilter_rules_clean()
{
	echo ":: [    LOG    ] :: xtables rules clean"
	local xtables=""; local table=""; local chain="";
	for xtables in ebtables arptables iptables ip6tables; do
		$xtables --version > /dev/null 2>&1 || continue
		for table in filter nat mangle raw security broute; do
			$xtables -t $table -F > /dev/null 2>&1
			$xtables -t $table -X > /dev/null 2>&1
			for chain in INPUT OUTPUT PREROUTING FORWARD POSTROUTING BROUTING; do
				$xtables -t $table -P $chain ACCEPT >/dev/null 2>&1
			done
		done
	done
	echo ":: [    LOG    ] :: nft rules clean"
	nft --version > /dev/null 2>&1 && {
	local line=""
	nft list tables | while read line; do
		nft delete $line
		done
	}
	echo ":: [    LOG    ] :: ipset rules clean"
	ipset --version > /dev/null 2>&1 && ipset destroy
	return 0
}
export -f netfilter_rules_clean

do_clean()
{
	for ns in client router server
	do
		ip netns |grep $ns && { \
		echo "netfilter_rules_clean" | ip netns exec $ns bash;
		ip netns del $ns; \
		}
	done
}

do_check()
{
	local ret=0
	ip netns exec client ping -W 40 -$(4or6 $ip_s) -I c_r $ip_s -c 5 -i 0.2 || { ret=1; }
	ip netns exec server ping -W 40 -$(4or6 $ip_c) -I s_r $ip_c -c 5 -i 0.2 || { ret=1; }
	return $ret
}

do_setup()
{
	set -x
	do_clean
	local i
	for i in client router server;do
	    ip netns add $i
	done

	if [[ "$1x" == "ipv6x" ]];then
		ip netns exec router sysctl -w net.ipv6.conf.all.forwarding=1
		ip_c=2001:db8:ffff:21::1
		ip_s=2001:db8:ffff:22::2
		ip_rc=2001:db8:ffff:21::fffe
		ip_rs=2001:db8:ffff:22::fffe
		N=64
		nodad=nodad
	elif [[ "$1x" == "ipv4x" ]];then
		ip netns exec router sysctl -w net.ipv4.ip_forward=1
		ip_c=10.167.1.1
		ip_s=10.167.2.2
		ip_rc=10.167.1.254
		ip_rs=10.167.2.254
		unset nodad
		N=24
	else
		set +x
		return 1;
	fi

	ip -d -n router -b /dev/stdin <<-EOF
		link add name r_c type veth peer name c_r netns client
		link add name r_s type veth peer name s_r netns server
		link set r_c up
		link set r_s up
		addr add $ip_rc/$N dev r_c $nodad
		addr add $ip_rs/$N dev r_s $nodad
		link set lo up
	EOF

	ip -d -n server -b /dev/stdin <<-EOF
		addr add $ip_s/$N dev s_r $nodad
		link set s_r up
		route add default via $ip_rs dev s_r
		link set lo up
	EOF

	ip -d -n client -b /dev/stdin <<-EOF
		addr add $ip_c/$N dev c_r $nodad
		link set c_r up
		route add default via $ip_rc dev c_r
		link set lo up
	EOF

	for i in tx rx tx-sctp-segmentation; do
		ip netns exec client ethtool -K c_r $i off
		ip netns exec server ethtool -K s_r $i off
	done 1>/dev/null 2>/dev/null

	sleep 2
	set +x
	do_check
}

run()
{
	local ns=$1; shift;
	# shellcheck disable=SC2124
	local cmd=$@;
	if [[ "$cmd" =~ "NoCheck" ]];then
		cmd=${cmd//NoCheck/}
		rlRun "ip netns exec $ns $cmd" 0-255 "NoCheck"
	elif [[ "$cmd" =~ "assert_fail" ]];then
		cmd=${cmd//assert_fail/}
		rlRun "ip netns exec $ns $cmd" 1-255 "assert_fail"
	else
		rlRun "ip netns exec $ns $cmd" 0
	fi
}
