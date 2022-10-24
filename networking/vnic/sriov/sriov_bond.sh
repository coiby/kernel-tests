#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/networking/vnic/sriov_bond
#   Author: Liang <liali@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc.
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

# add vfs to mode2 bond in vm
# check layer2 hash for IPv4 and IPv6 streams
# check layer2+3 hash for IPv4 and IPv6 streams
# check layer3+4 hash for IPv4 and IPv6 streams
# check if receiving duplicate packet
# check failover when peer switch port is down
# create vlan over mode2 bond, check layer2 hash too
# create vlan over mode2 bond, check failover when peer switch port is down
sriov_test_bond_mode2()
{
	$dbg_flag
	yum install -y tcpdump wireshark nmap-ncat
		test_name="sriov_bonding_mode2"
		client_ip4_1="172.30.$ipaddr.1"
		client_ip4_2="172.31.$ipaddr.2"
		server_ip4_1="172.30.$ipaddr.5"
		server_ip4_2="172.31.$ipaddr.5"
		client_ip6_1="2009:$ipaddr:11::1"
		server_ip6_1="2009:$ipaddr:11::3"
		client_ip6_2="2009:$ipaddr:12::2"
		server_ip6_2="2009:$ipaddr:12::3"
		client_ip4_vlan_1="172.40.$ipaddr.1"
		client_ip4_vlan_2="172.41.$ipaddr.2"
		server_ip4_vlan_1="172.40.$ipaddr.5"
		server_ip4_vlan_2="172.41.$ipaddr.5"
		veth_mac=$(printf "00:33:32:23:%02x:09" $ipaddr)
		# use for hash
		macA=$(printf "00:33:32:22:%02x:01" $ipaddr)
		macB=$(printf "00:33:32:22:%02x:02" $ipaddr)
	result=0

	if i_am_server; then
			#rlRun "disable_ipv6_ra $nic_test $ipaddr 2"
			rlRun "ip link set $nic_test up"
			rlRun "ip addr add ${server_ip4_1}/24 dev $nic_test"
		sleep 1
			rlRun "ip addr add ${server_ip4_2}/24 dev $nic_test"
			sleep 1
			rlRun "ip addr add ${server_ip6_1}/64 dev $nic_test"
			sleep 1
			rlRun "ip addr add ${server_ip6_2}/64 dev $nic_test"
		rlRun "ip link add link $nic_test name $nic_test.3 type vlan id 3"
		rlRun "ip link set $nic_test.3 up"
			rlRun "ip addr add ${server_ip4_vlan_1}/24 dev $nic_test.3"
		sleep 1
			rlRun "ip addr add ${server_ip4_vlan_2}/24 dev $nic_test.3"
			rlRun "nc -l 20004 -k &"
			rlRun "sync_set client ${test_name}_phase1"
			rlRun "sync_wait client ${test_name}_phase1_end"

			rlRun "sync_set client ${test_name}_phase2"
			rlRun "sync_wait client ${test_name}_phase2_end"
			rlRun "sync_set client ${test_name}_phase3"
			rlRun "sync_wait client ${test_name}_phase3_end"
			rlRun "sync_set client ${test_name}_phase4"
			rlRun "sync_wait client ${test_name}_phase4_end"
			rlRun "ping -c10 $client_ip4_1" 0-254
			rlRun "sync_set client ${test_name}_phase5"
			rlRun "sync_wait client ${test_name}_phase5_end"
			rlRun "ping6 -c10 $client_ip6_1" 0-254
			rlRun "sync_set client ${test_name}_phase6"
			rlRun "sync_wait client ${test_name}_phase6_end"

			pkill nc
			ip addr flush $nic_test
		ip link del $nic_test.3
			#rlRun "enable_ipv6_ra $iface1"
	else
		if [ "$NIC_DRIVER" = "mlx4_en" ];then
			NIC_NUM=2
					local test_iface=$(get_required_iface)
					local iface1=$(echo $test_iface | awk '{print $1}')
					local iface2=$(echo $test_iface | awk '{print $2}')
					ip link set $iface1 up

					local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
					local if2_bus=$(sriov_get_pf_bus_info $iface2 0)

					#vf will be created paired on dual port mlx NIC
					if ! sriov_create_vfs $iface1 0 1;then
							let result++
							rlFail "${test_name} failed: can't create vfs."

					fi
					ip link set $iface1 up
					ip link set $iface2 up
					sleep 10

					local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
					local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

					ip link set $iface1 vf 0 trust on
					ip link set $iface1 vf 0 spoofchk off
					ip link set $iface2 vf 0 trust on
					ip link set $iface2 vf 0 spoofchk off

					vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

					if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
							let result++
							rlFail "${test_name} failed: can't attach vf to vm."
					fi

					vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
					vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

					get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
					swcfg setup_port_channel_without_lacp $switch_name "$port_list" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
					if [ -n "$kick_list" ];then
							rlLog "$kick_list are not on the same switch, kicked."
					fi

					vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
					vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

					vmsh run_cmd $vm1 "echo \$(sed -n 1p /tmp/vfs) > /root/testiface1"
					vmsh run_cmd $vm1 "echo \$(sed -n 2p /tmp/vfs) > /root/testiface2"
				elif [ "$NIC_DRIVER" = "cxgb4" ];then
			NIC_NUM=2
					local test_iface=$(get_required_iface)
					local iface1=$(echo $test_iface | awk '{print $1}')
					local iface2=$(echo $test_iface | awk '{print $2}')
					ip link set $iface1 up
					local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
					local if2_bus=$(sriov_get_pf_bus_info $iface2 0)

					if ! sriov_create_vfs $iface1 0 1 || \
							! sriov_create_vfs $iface2 1 1;then
							let result++
							rlFail "${test_name} failed: can't create vfs."

					fi
					ip link set $iface1 up
					ip link set $iface2 up
					sleep 10

					local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
					local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

					ip link set $iface1 vf 0 trust on
					ip link set $iface1 vf 0 spoofchk off
					ip link set $iface2 vf 1 trust on
					ip link set $iface2 vf 1 spoofchk off

					if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
							! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
							let result++
							rlFail "${test_name} failed: can't attach vf to vm."
					fi
					get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
					swcfg setup_port_channel_without_lacp $switch_name "$port_list"  || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
					if [ -n "$kick_list" ];then
							rlFail "$kick_list are not on the same switch, kicked."
					fi

					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /root/testiface1"
					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /root/testiface2"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface1) down"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface2) down"

				else
				NIC_NUM=2
					local test_iface=$(get_required_iface)
					local iface1=$(echo $test_iface | awk '{print $1}')
					local iface2=$(echo $test_iface | awk '{print $2}')
					ip link set $iface1 up

					local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
					local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
					if [ "$if1_bus" = "$if2_bus" ];then
							rlLog "warning: two ifs belong to a dual port NIC"
					fi
					if ! sriov_create_vfs $iface1 0 2 || \
							! sriov_create_vfs $iface2 0 2;then
							let result++
							rlFail "${test_name} failed: can't create vfs."

					fi
					ip link set $iface1 up
					ip link set $iface2 up
					sleep 10
				
			local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
					local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"
		  		local mac3="00:de:ad:$(printf %02x $ipaddr):01:03"
		  		local mac4="00:de:ad:$(printf %02x $ipaddr):01:04"
		  		local mac5="00:de:ad:$(printf %02x $ipaddr):01:05"
		  		local mac6="00:de:ad:$(printf %02x $ipaddr):01:06"

					ip link set $iface1 vf 0 trust on
					ip link set $iface1 vf 0 spoofchk off
					ip link set $iface2 vf 1 trust on
					ip link set $iface2 vf 1 spoofchk off

					if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
							! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
							let result++
							rlFail "${test_name} failed: can't attach vf to vm."
					fi
					get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
					swcfg setup_port_channel_without_lacp $switch_name "$port_list"  || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
					if [ -n "$kick_list" ];then
							rlLog "$kick_list are not on the same switch, kicked."
					fi

					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /root/testiface1"
					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /root/testiface2"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface1) down"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface2) down"
				fi

		rlRun "sync_wait server ${test_name}_phase1"
		
		rlLog "layer2 hash ipv4"
		local cmd=(
			{loginctl enable-linger root}
			{yum install -y tcpdump wireshark nmap-ncat}
						{modprobe -r bonding}
						{modprobe -v bonding mode=2 miimon=100 max_bonds=1}
						{echo layer2 \> /sys/class/net/bond0/bonding/xmit_hash_policy}
						{ip link set bond0 address $macA}
						{ip link set bond0 up}
						{ifenslave bond0 \$\(cat /root/testiface1\)}
						{ifenslave bond0 \$\(cat /root/testiface2\)}
						{sleep 2}
						{cat \/proc\/net\/bonding\/bond0}
						{ip addr add $client_ip4_1/24 dev bond0}
			{sleep 1}
						{ip addr add $client_ip4_2/24 dev bond0}
			{sleep 1}
						{ip addr add $client_ip6_1/64 dev bond0}
			{sleep 1}
						{ip addr add $client_ip6_2/64 dev bond0}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} failed:ifenslave failed";let result++; }
				fi
		
		vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 3 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		rlRun "sync_set server ${test_name}_phase1_end"
		rlRun "sync_wait server ${test_name}_phase2"

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_1 -w slave2.pcap \&}
					{sleep 3}
					{ping -c 20 $server_ip4_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

			vmsh run_cmd $vm1 "ip link set bond0 down;ip link set bond0 address $macB;ip link set bond0 up;sleep 30;"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi


		local cmd=(
						{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_1 -w slave1.pcap \&}
						{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_1 -w slave2.pcap \&}
						{sleep 3}
						{ping -c 20 $server_ip4_1}
						{pkill tcpdump\;sleep 3\;}
				)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlLog "layer2 hash ipv6"
		vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "ip link set bond0 address $macA"
			vmsh run_cmd $vm1 "echo layer2 > /sys/class/net/bond0/bonding/xmit_hash_policy"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			sleep 30
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 10 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

		vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "ip link set bond0 address $macB"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0" 
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			sleep 30
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 10 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlRun "sync_set server ${test_name}_phase2_end"
			rlRun "sync_wait server ${test_name}_phase3"
		
		rlLog "layer2+3 ipv4"

			vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "echo layer2+3 > /sys/class/net/bond0/bonding/xmit_hash_policy"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0" 
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 5 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 5 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_1 -w slave2.pcap \&}
					{sleep 3}
					{ping -c 20 $server_ip4_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_2 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_2 -w slave2.pcap \&}
					{sleep 3}
					{ping -c 20 $server_ip4_2}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlLog "layer2+3 hash ipv6"
		
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_2 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_2 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_2}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlRun "sync_set server ${test_name}_phase3_end"
			rlRun "sync_wait server ${test_name}_phase4"
		rlLog "layer3+4 ipv4"

			vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "echo layer3+4 > /sys/class/net/bond0/bonding/xmit_hash_policy"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
		rlLog "hash with src port 20000"
			src_ip=$client_ip4_1
			dst_ip=$server_ip4_1
			src_port=20000
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream1 on both slaves"
				let result++
			fi
					stream1_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
					stream1_outif=slave2
			fi

			rlLog "hash with src port 20002"
			src_ip=$client_ip4_1
			dst_ip=$server_ip4_1
			src_port=20002
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream2 on both slaves"
				let result++
			fi
					stream2_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
					stream2_outif=slave2
			fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlLog "layer3+4 hash ipv6"
		rlLog "hash with src port 20000"
			src_ip=$client_ip6_1
			dst_ip=$server_ip6_1
			src_port=20000
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream1 on both slaves"
				let result++
			fi
					stream1_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
					stream1_outif=slave2
			fi

			rlLog "hash with src port 20002"
			src_ip=$client_ip6_1
			dst_ip=$server_ip6_1
			src_port=20002
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream2 on both slaves"
				let result++
			fi
					stream2_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
					stream2_outif=slave2
			fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

			rlRun "sync_set server ${test_name}_phase4_end"
			rlRun "sync_wait server ${test_name}_phase5"

		rlLog "check ipv4 duplicate packet"
		vmsh run_cmd $vm1 "ping -c10 $server_ip4_1"
		vmsh run_cmd $vm1 "ping -c10 $server_ip4_1 > /tmp/mode2_output"
		if vmsh run_cmd $vm1 "cat /tmp/mode2_output | grep -i dup";then
			rlFail "Received duplicate ipv4 packets"
			vmsh run_cmd $vm1 "cat /tmp/mode2_output"
			let resultl++
		fi

			rlRun "sync_set server ${test_name}_phase5_end"
			rlRun "sync_wait server ${test_name}_phase6"

		rlLog "check ipv6 duplicate packet"
				vmsh run_cmd $vm1 "ping -c10 $server_ip6_1"
				vmsh run_cmd $vm1 "ping -c10 $server_ip6_1 > /tmp/mode2_output"
				if vmsh run_cmd $vm1 "cat /tmp/mode2_output | grep -i dup";then
						rlFail "Received duplicate ipv6 packets"
						vmsh run_cmd $vm1 "cat /tmp/mode2_output"
						let resultl++
				fi

		rlLog "test connection when one slave is down"
		get_iface_sw_port $iface1 sw1 p1 k
		get_iface_sw_port $iface2 sw2 p2 k
		swcfg port_down $sw1 $p1
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi
		swcfg port_up $sw1 $p1
		swcfg port_down $sw2 $p2
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi
		swcfg port_up $sw2 $p2
		sleep 10

		rlLog "bond with arp monitor"
		vmsh run_cmd $vm1 "modprobe -rv bonding"
			vmsh run_cmd $vm1 "modprobe -v bonding mode=2 arp_interval=100 arp_ip_target=$server_ip4_1 max_bonds=1"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /root/testiface1) \$(cat /root/testiface2)"
			vmsh run_cmd $vm1 "ip addr add $client_ip4_1/24 dev bond0"
		sleep 1
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 3 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "modprobe -rv bonding;sleep 1;"

: <<- EOF
		rlLog "miimon monitor bond in bridge"
		vmsh run_cmd $vm1 "modprobe -v bonding mode=2 miimon=100 max_bonds=1 xmit_hash_policy=layer2+3"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /root/testiface1) \$(cat /root/testiface2)"
			vmsh run_cmd $vm1 "ip netns add ns1"
			vmsh run_cmd $vm1 "ip link add name veth0 type veth peer name veth1"
			vmsh run_cmd $vm1 "ip link set veth0 netns ns1"
			#vmsh run_cmd $vm1 "ip netns exec ns1 ip link set veth0 address $veth_mac"
			vmsh run_cmd $vm1 "ip netns exec ns1 ip link set veth0 up"
			vmsh run_cmd $vm1 "ip link set veth1 up"
			vmsh run_cmd $vm1 "ip netns exec ns1 ip addr add $client_ip4_1/24 dev veth0"
		sleep 1
			vmsh run_cmd $vm1 "ip netns exec ns1 ip addr add $client_ip4_2/24 dev veth0"
		sleep 1
			vmsh run_cmd $vm1 "ip netns exec ns1 ip addr add $client_ip6_1/64 dev veth0"
		sleep 1
			vmsh run_cmd $vm1 "ip link add name br0 type bridge"
			vmsh run_cmd $vm1 "ip link set br0 up"
			vmsh run_cmd $vm1 "ip link set veth1 master br0"
			vmsh run_cmd $vm1 "ip link set bond0 master br0"
			vmsh run_cmd $vm1 "ip netns exec ns1 timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "ip netns exec ns1 timeout 90s bash -c \"until ping6 -c 3 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		vmsh run_cmd $vm1 "modprobe -rv bonding"
			vmsh run_cmd $vm1 "modprobe -v bonding mode=2 arp_interval=100 arp_ip_target=$server_ip4_1 max_bonds=1"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /root/testiface1) \$(cat /root/testiface2)"
			vmsh run_cmd $vm1 "ip link set bond0 master br0"
			vmsh run_cmd $vm1 "ip netns exec ns1 timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "modprobe -rv bonding"
			vmsh run_cmd $vm1 "ip link del br0"
			vmsh run_cmd $vm1 "ip netns del ns1"
			vmsh run_cmd $vm1 "ip link del veth0 &>/dev/null"
			vmsh run_cmd $vm1 "ip link del veth1 &>/dev/null"
EOF
		rlLog "vlan over bond"
		local cmd=(
			{modprobe -rv bonding}
				{modprobe -v bonding mode=2 miimon=100 max_bonds=1}
						{echo layer2 \> /sys/class/net/bond0/bonding/xmit_hash_policy}
				{ip link set bond0 up}
				{ifenslave bond0 \$\(cat /root/testiface1\) \$\(cat /root/testiface2\)}
						{ip link add link bond0 name bond0\.3 type vlan id 3}
						{ip link set bond0\.3 address $macA}
						{ip link set bond0\.3 up}
				{ip addr add $client_ip4_vlan_1/24 dev bond0\.3}
			{sleep 1}
				{ip addr add $client_ip4_vlan_2/24 dev bond0\.3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		rlLog "vlan over bnod: layer2 hash ipv4"
		vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_vlan_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_vlan_1 failed";let result++; }
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out -w slave2.pcap \&}
					{sleep 3}
					{ping -c 20 $server_ip4_vlan_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

			vmsh run_cmd $vm1 "ip link set bond0 down;ip link set bond0.3 address $macB;ip link set bond0 up;sleep 30;"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 10 $server_ip4_vlan_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_vlan_1 failed";let result++; }
				fi

		local cmd=(
						{tcpdump -p -i \$\(cat /root/testiface1\) -Q out -w slave1.pcap \&}
						{tcpdump -p -i \$\(cat /root/testiface2\) -Q out -w slave2.pcap \&}
						{sleep 3}
						{ping -c 20 $server_ip4_vlan_1}
						{pkill tcpdump\;sleep 3\;}
				)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

				rlLog "vlan over bond: test connection when one slave is down"
				get_iface_sw_port $iface1 sw1 p1 k
				get_iface_sw_port $iface2 sw2 p2 k
				swcfg port_down $sw1 $p1
				vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_vlan_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_vlan_1 failed";let result++; }
				fi
				vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_vlan_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_vlan_2 failed";let result++; }
				fi
				swcfg port_up $sw1 $p1
				swcfg port_down $sw2 $p2
				vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_vlan_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_vlan_1 failed";let result++; }
				fi
				vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_vlan_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_vlan_2 failed";let result++; }
				fi
				swcfg port_up $sw2 $p2

		vmsh run_cmd $vm1 "modprobe -rv bonding"

		get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list
		swcfg cleanup_port_channel $switch_name "$port_list" 

		if [ "$NIC_DRIVER" = "mlx4_en" ];then
					sriov_detach_vf_from_vm $iface1 0 1 $vm1
					sriov_remove_vfs $iface1 0
				elif [ "$NIC_DRIVER" = "cxgb4" ];then
					sriov_detach_vf_from_vm $iface1 0 1 $vm1
					sriov_detach_vf_from_vm $iface2 1 1 $vm1
					sriov_remove_vfs $iface1 0
					sriov_remove_vfs $iface2 1
				else
					sriov_detach_vf_from_vm $iface1 0 1 $vm1
					sriov_detach_vf_from_vm $iface2 0 2 $vm1
					sriov_remove_vfs $iface1 0
					sriov_remove_vfs $iface2 0
				fi

				ip addr flush $iface1
				ip addr flush $iface2
			rlRun "sync_set server ${test_name}_phase6_end"
	fi
}

# This case is same with sriov_test_bond_mode2 execpt specifying vlan id when attaching vf to vm
# add vfs to mode2 bond in vm
# check layer2 hash for IPv4 and IPv6 streams
# check layer2+3 hash for IPv4 and IPv6 streams
# check layer3+4 hash for IPv4 and IPv6 streams
# check if receiving duplicate packet
# check failover when peer switch port is down
sriov_test_bond_mode2_vlan()
{
	$dbg_flag
	yum install -y tcpdump wireshark nmap-ncat
		test_name="sriov_bonding_mode2_vlan"
		client_ip4_1="172.30.$ipaddr.1"
		client_ip4_2="172.31.$ipaddr.2"
		server_ip4_1="172.30.$ipaddr.5"
		server_ip4_2="172.31.$ipaddr.5"
		client_ip6_1="2009:$ipaddr:11::1"
		server_ip6_1="2009:$ipaddr:11::3"
		client_ip6_2="2009:$ipaddr:12::2"
		server_ip6_2="2009:$ipaddr:12::3"
		veth_mac=$(printf "00:33:32:23:%02x:09" $ipaddr)
		# use for hash
		macA=$(printf "00:33:32:22:%02x:01" $ipaddr)
		macB=$(printf "00:33:32:22:%02x:02" $ipaddr)
	result=0

	if i_am_server; then
			#rlRun "disable_ipv6_ra $nic_test $ipaddr 2"
			rlRun "ip link set $nic_test up"
		rlRun "ip link add link $nic_test name $nic_test.3 type vlan id 3"
		rlRun "ip link set $nic_test.3 up"
			rlRun "ip addr add ${server_ip4_1}/24 dev $nic_test.3"
		sleep 1
			rlRun "ip addr add ${server_ip4_2}/24 dev $nic_test.3"
			sleep 1
			rlRun "ip addr add ${server_ip6_1}/64 dev $nic_test.3"
			sleep 1
			rlRun "ip addr add ${server_ip6_2}/64 dev $nic_test.3"
			rlRun "nc -l 20004 -k &"
			rlRun "sync_set client ${test_name}_phase1"
			rlRun "sync_wait client ${test_name}_phase1_end"

			rlRun "sync_set client ${test_name}_phase2"
			rlRun "sync_wait client ${test_name}_phase2_end"
			rlRun "sync_set client ${test_name}_phase3"
			rlRun "sync_wait client ${test_name}_phase3_end"
			rlRun "sync_set client ${test_name}_phase4"
			rlRun "sync_wait client ${test_name}_phase4_end"
			rlRun "ping -c10 $client_ip4_1" 0-254
			rlRun "sync_set client ${test_name}_phase5"
			rlRun "sync_wait client ${test_name}_phase5_end"
			rlRun "ping6 -c10 $client_ip6_1" 0-254
			rlRun "sync_set client ${test_name}_phase6"
			rlRun "sync_wait client ${test_name}_phase6_end"

			pkill nc
			ip addr flush $nic_test
		ip link del $nic_test.3
			#rlRun "enable_ipv6_ra $iface1"
	else
		if [ "$NIC_DRIVER" = "mlx4_en" ];then
			NIC_NUM=2
					local test_iface=$(get_required_iface)
					local iface1=$(echo $test_iface | awk '{print $1}')
					local iface2=$(echo $test_iface | awk '{print $2}')
					ip link set $iface1 up

					local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
					local if2_bus=$(sriov_get_pf_bus_info $iface2 0)

					#vf will be created paired on dual port mlx NIC
					if ! sriov_create_vfs $iface1 0 1;then
							let result++
							rlFail "${test_name} failed: can't create vfs."

					fi
					ip link set $iface1 up
					ip link set $iface2 up
					sleep 10

					local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
					local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

					ip link set $iface1 vf 0 trust on
					ip link set $iface1 vf 0 spoofchk off
					ip link set $iface2 vf 0 trust on
					ip link set $iface2 vf 0 spoofchk off

					vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

					if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 3 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2 3;then
							let result++
							rlFail "${test_name} failed: can't attach vf to vm."
					fi

					vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
					vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

					get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
					swcfg setup_port_channel_without_lacp $switch_name "$port_list" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
					if [ -n "$kick_list" ];then
							rlLog "$kick_list are not on the same switch, kicked."
					fi

					vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
					vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

					vmsh run_cmd $vm1 "echo \$(sed -n 1p /tmp/vfs) > /root/testiface1"
					vmsh run_cmd $vm1 "echo \$(sed -n 2p /tmp/vfs) > /root/testiface2"
				elif [ "$NIC_DRIVER" = "cxgb4" ];then
			NIC_NUM=2
					local test_iface=$(get_required_iface)
					local iface1=$(echo $test_iface | awk '{print $1}')
					local iface2=$(echo $test_iface | awk '{print $2}')
					ip link set $iface1 up
					local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
					local if2_bus=$(sriov_get_pf_bus_info $iface2 0)

					if ! sriov_create_vfs $iface1 0 1 || \
							! sriov_create_vfs $iface2 1 1;then
							let result++
							rlFail "${test_name} failed: can't create vfs."

					fi
					ip link set $iface1 up
					ip link set $iface2 up
					sleep 10

					local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
					local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

					ip link set $iface1 vf 0 trust on
					ip link set $iface1 vf 0 spoofchk off
					ip link set $iface2 vf 1 trust on
					ip link set $iface2 vf 1 spoofchk off

					if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 3 || \
							! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2 3;then
							let result++
							rlFail "${test_name} failed: can't attach vf to vm."
					fi
					get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
					swcfg setup_port_channel_without_lacp $switch_name "$port_list"  || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
					if [ -n "$kick_list" ];then
							rlFail "$kick_list are not on the same switch, kicked."
					fi

					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /root/testiface1"
					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /root/testiface2"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface1) down"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface2) down"

				else
				NIC_NUM=2
					local test_iface=$(get_required_iface)
					local iface1=$(echo $test_iface | awk '{print $1}')
					local iface2=$(echo $test_iface | awk '{print $2}')
					ip link set $iface1 up

					local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
					local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
					if [ "$if1_bus" = "$if2_bus" ];then
							rlLog "warning: two ifs belong to a dual port NIC"
					fi
					if ! sriov_create_vfs $iface1 0 2 || \
							! sriov_create_vfs $iface2 0 2;then
							let result++
							rlFail "${test_name} failed: can't create vfs."

					fi
					ip link set $iface1 up
					ip link set $iface2 up
					sleep 10
				
			local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
					local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"
		  		local mac3="00:de:ad:$(printf %02x $ipaddr):01:03"
		  		local mac4="00:de:ad:$(printf %02x $ipaddr):01:04"
		  		local mac5="00:de:ad:$(printf %02x $ipaddr):01:05"
		  		local mac6="00:de:ad:$(printf %02x $ipaddr):01:06"

					ip link set $iface1 vf 0 trust on
					ip link set $iface1 vf 0 spoofchk off
					ip link set $iface2 vf 1 trust on
					ip link set $iface2 vf 1 spoofchk off

					if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 3 || \
							! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2 3;then
							let result++
							rlFail "${test_name} failed: can't attach vf to vm."
					fi
					get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
					swcfg setup_port_channel_without_lacp $switch_name "$port_list"  || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
					if [ -n "$kick_list" ];then
							rlLog "$kick_list are not on the same switch, kicked."
					fi

					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /root/testiface1"
					vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /root/testiface2"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface1) down"
					vmsh run_cmd $vm1 "ip link set \$(cat /root/testiface2) down"
				fi

		rlRun "sync_wait server ${test_name}_phase1"
		
		rlLog "layer2 hash ipv4"
		local cmd=(
			{loginctl enable-linger root}
			{yum install -y tcpdump wireshark nmap-ncat}
						{modprobe -r bonding}
						{modprobe -v bonding mode=2 miimon=100 max_bonds=1}
						{echo layer2 \> /sys/class/net/bond0/bonding/xmit_hash_policy}
						{ip link set bond0 address $macA}
						{ip link set bond0 up}
						{ifenslave bond0 \$\(cat /root/testiface1\)}
						{ifenslave bond0 \$\(cat /root/testiface2\)}
						{sleep 2}
						{cat \/proc\/net\/bonding\/bond0}
						{ip addr add $client_ip4_1/24 dev bond0}
			{sleep 1}
						{ip addr add $client_ip4_2/24 dev bond0}
			{sleep 1}
						{ip addr add $client_ip6_1/64 dev bond0}
			{sleep 1}
						{ip addr add $client_ip6_2/64 dev bond0}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} failed:ifenslave failed";let result++; }
				fi
		
		vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 3 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		rlRun "sync_set server ${test_name}_phase1_end"
		rlRun "sync_wait server ${test_name}_phase2"

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_1 -w slave2.pcap \&}
					{sleep 3}
					{ping -c 20 $server_ip4_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

			vmsh run_cmd $vm1 "ip link set bond0 down;ip link set bond0 address $macB;ip link set bond0 up;sleep 30;"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi


		local cmd=(
						{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_1 -w slave1.pcap \&}
						{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_1 -w slave2.pcap \&}
						{sleep 3}
						{ping -c 20 $server_ip4_1}
						{pkill tcpdump\;sleep 3\;}
				)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlLog "layer2 hash ipv6"
		vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "ip link set bond0 address $macA"
			vmsh run_cmd $vm1 "echo layer2 > /sys/class/net/bond0/bonding/xmit_hash_policy"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			sleep 30
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 10 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

		vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "ip link set bond0 address $macB"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0" 
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			sleep 30
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 10 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlRun "sync_set server ${test_name}_phase2_end"
			rlRun "sync_wait server ${test_name}_phase3"
		
		rlLog "layer2+3 ipv4"

			vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "echo layer2+3 > /sys/class/net/bond0/bonding/xmit_hash_policy"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0" 
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 5 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 5 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_1 -w slave2.pcap \&}
					{sleep 3}
					{ping -c 20 $server_ip4_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

		local cmd=(
					{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp and dst $server_ip4_2 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp and dst $server_ip4_2 -w slave2.pcap \&}
					{sleep 3}
					{ping -c 20 $server_ip4_2}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlLog "layer2+3 hash ipv6"
		
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_1 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_1}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream1 on both slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
						local stream1_outif=slave2
				fi

		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) -Q out icmp6 and ip6 dst $server_ip6_2 -w slave1.pcap \&}
					{tcpdump -p -i \$\(cat /root/testiface2\) -Q out icmp6 and ip6 dst $server_ip6_2 -w slave2.pcap \&}
					{sleep 3}
					{ping6 -c 20 $server_ip6_2}
					{pkill tcpdump\;sleep 3\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
				if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap | grep -q -i 'echo request'";then
						if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "saw stream2 on both slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave1
				else
						if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap | grep -q -i 'echo request'";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
						local stream2_outif=slave2
				fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlRun "sync_set server ${test_name}_phase3_end"
			rlRun "sync_wait server ${test_name}_phase4"
		rlLog "layer3+4 ipv4"

			vmsh run_cmd $vm1 "ip link set bond0 down"
			vmsh run_cmd $vm1 "echo layer3+4 > /sys/class/net/bond0/bonding/xmit_hash_policy"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
		rlLog "hash with src port 20000"
			src_ip=$client_ip4_1
			dst_ip=$server_ip4_1
			src_port=20000
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream1 on both slaves"
				let result++
			fi
					stream1_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
					stream1_outif=slave2
			fi

			rlLog "hash with src port 20002"
			src_ip=$client_ip4_1
			dst_ip=$server_ip4_1
			src_port=20002
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) dst host $server_ip4_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream2 on both slaves"
				let result++
			fi
					stream2_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
					stream2_outif=slave2
			fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

		rlLog "layer3+4 hash ipv6"
		rlLog "hash with src port 20000"
			src_ip=$client_ip6_1
			dst_ip=$server_ip6_1
			src_port=20000
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream1 on both slaves"
				let result++
			fi
					stream1_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream1 on either slave1 and slave2"
				let result++
			fi
					stream1_outif=slave2
			fi

			rlLog "hash with src port 20002"
			src_ip=$client_ip6_1
			dst_ip=$server_ip6_1
			src_port=20002
			dst_port=20004
			rlLog "src_port is $src_port, dst port is $dst_port, src_ip is $src_ip, dst_ip is $dst_ip"
		local cmd=(
			{tcpdump -p -i \$\(cat /root/testiface1\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave1.pcap \&}
				{tcpdump -p -i \$\(cat /root/testiface2\) ip6 dst $server_ip6_1 and dst port $dst_port -Q out -w slave2.pcap \&}
				{sleep 3}
			{for i in \{1\.\.10\}\;do nc -s $src_ip -p $src_port $dst_ip $dst_port \<\<\< \"Hello World!\"\;done}
				{sleep 2\;pkill tcpdump\;sleep 2\;}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			if vmsh run_cmd $vm1 "tcpdump -r slave1.pcap -enn | grep -q $src_ip\.$src_port";then
					if vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "saw stream2 on both slaves"
				let result++
			fi
					stream2_outif=slave1
			else
					if ! vmsh run_cmd $vm1 "tcpdump -r slave2.pcap -enn | grep -q $src_ip\.$src_port";then
				rlFail "no stream2 on either slave1 and slave2"
				let result++
			fi
					stream2_outif=slave2
			fi

			if [ "$stream1_outif" == "$stream2_outif" ];then
					rlFail "two streams dispatched to a same interface. $stream1_outif vs $stream2_outif"
			else
					rlPass "two streams dispatched to different interface. $stream1_outif vs $stream2_outif"
			fi

			rlRun "sync_set server ${test_name}_phase4_end"
			rlRun "sync_wait server ${test_name}_phase5"

		rlLog "check ipv4 duplicate packet"
		vmsh run_cmd $vm1 "ping -c10 $server_ip4_1"
		vmsh run_cmd $vm1 "ping -c10 $server_ip4_1 > /tmp/mode2_output"
		if vmsh run_cmd $vm1 "cat /tmp/mode2_output | grep -i dup";then
			rlFail "Received duplicate ipv4 packets"
			vmsh run_cmd $vm1 "cat /tmp/mode2_output"
			let resultl++
		fi

			rlRun "sync_set server ${test_name}_phase5_end"
			rlRun "sync_wait server ${test_name}_phase6"

		rlLog "check ipv6 duplicate packet"
				vmsh run_cmd $vm1 "ping -c10 $server_ip6_1"
				vmsh run_cmd $vm1 "ping -c10 $server_ip6_1 > /tmp/mode2_output"
				if vmsh run_cmd $vm1 "cat /tmp/mode2_output | grep -i dup";then
						rlFail "Received duplicate ipv6 packets"
						vmsh run_cmd $vm1 "cat /tmp/mode2_output"
						let resultl++
				fi

		rlLog "test connection when one slave is down"
		get_iface_sw_port $iface1 sw1 p1 k
		get_iface_sw_port $iface2 sw2 p2 k
		swcfg port_down $sw1 $p1
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi
		swcfg port_up $sw1 $p1
		swcfg port_down $sw2 $p2
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 3 $server_ip4_2; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_2 failed";let result++; }
				fi
		swcfg port_up $sw2 $p2
		sleep 10

		rlLog "bond with arp monitor"
		vmsh run_cmd $vm1 "modprobe -rv bonding"
			vmsh run_cmd $vm1 "modprobe -v bonding mode=2 arp_interval=100 arp_ip_target=$server_ip4_1 max_bonds=1"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /root/testiface1) \$(cat /root/testiface2)"
			vmsh run_cmd $vm1 "ip addr add $client_ip4_1/24 dev bond0"
		sleep 1
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_1}/64 dev bond0"
			vmsh run_cmd $vm1 "ip addr add ${client_ip6_2}/64 dev bond0"
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "timeout 90s bash -c \"until ping6 -c 3 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "modprobe -rv bonding;sleep 1;"

: <<- EOF
		rlLog "miimon monitor bond in bridge"
		vmsh run_cmd $vm1 "modprobe -v bonding mode=2 miimon=100 max_bonds=1 xmit_hash_policy=layer2+3"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /root/testiface1) \$(cat /root/testiface2)"
			vmsh run_cmd $vm1 "ip netns add ns1"
			vmsh run_cmd $vm1 "ip link add name veth0 type veth peer name veth1"
			vmsh run_cmd $vm1 "ip link set veth0 netns ns1"
			#vmsh run_cmd $vm1 "ip netns exec ns1 ip link set veth0 address $veth_mac"
			vmsh run_cmd $vm1 "ip netns exec ns1 ip link set veth0 up"
			vmsh run_cmd $vm1 "ip link set veth1 up"
			vmsh run_cmd $vm1 "ip netns exec ns1 ip addr add $client_ip4_1/24 dev veth0"
		sleep 1
			vmsh run_cmd $vm1 "ip netns exec ns1 ip addr add $client_ip4_2/24 dev veth0"
		sleep 1
			vmsh run_cmd $vm1 "ip netns exec ns1 ip addr add $client_ip6_1/64 dev veth0"
		sleep 1
			vmsh run_cmd $vm1 "ip link add name br0 type bridge"
			vmsh run_cmd $vm1 "ip link set br0 up"
			vmsh run_cmd $vm1 "ip link set veth1 master br0"
			vmsh run_cmd $vm1 "ip link set bond0 master br0"
			vmsh run_cmd $vm1 "ip netns exec ns1 timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "ip netns exec ns1 timeout 90s bash -c \"until ping6 -c 3 $server_ip6_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip6_1 failed";let result++; }
				fi

		vmsh run_cmd $vm1 "modprobe -rv bonding"
			vmsh run_cmd $vm1 "modprobe -v bonding mode=2 arp_interval=100 arp_ip_target=$server_ip4_1 max_bonds=1"
			vmsh run_cmd $vm1 "ip link set bond0 up"
			vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /root/testiface1) \$(cat /root/testiface2)"
			vmsh run_cmd $vm1 "ip link set bond0 master br0"
			vmsh run_cmd $vm1 "ip netns exec ns1 timeout 90s bash -c \"until ping -c 10 $server_ip4_1; do sleep 5; done\""
				if [ $? -ne 0 ];then
						{ rlFail "${test_name} ping $server_ip4_1 failed";let result++; }
				fi
			vmsh run_cmd $vm1 "modprobe -rv bonding"
			vmsh run_cmd $vm1 "ip link del br0"
			vmsh run_cmd $vm1 "ip netns del ns1"
			vmsh run_cmd $vm1 "ip link del veth0 &>/dev/null"
			vmsh run_cmd $vm1 "ip link del veth1 &>/dev/null"
EOF

		get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list
		swcfg cleanup_port_channel $switch_name "$port_list" 

		if [ "$NIC_DRIVER" = "mlx4_en" ];then
					sriov_detach_vf_from_vm $iface1 0 1 $vm1
					sriov_remove_vfs $iface1 0
				elif [ "$NIC_DRIVER" = "cxgb4" ];then
					sriov_detach_vf_from_vm $iface1 0 1 $vm1
					sriov_detach_vf_from_vm $iface2 1 1 $vm1
					sriov_remove_vfs $iface1 0
					sriov_remove_vfs $iface2 1
				else
					sriov_detach_vf_from_vm $iface1 0 1 $vm1
					sriov_detach_vf_from_vm $iface2 0 2 $vm1
					sriov_remove_vfs $iface1 0
					sriov_remove_vfs $iface2 0
				fi

				ip addr flush $iface1
				ip addr flush $iface2
			rlRun "sync_set server ${test_name}_phase6_end"
	fi
}
