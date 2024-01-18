#!/bin/bash
# shellcheck disable=SC1083,SC2048,SC1010
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

sriov_test_vmvf_bond_remote()
{
	log_header "VMVF_BOND <---> REMOTE" $result_file
	local result=0
	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bond_vmvf_remote_start
		sync_wait client test_vmvf_bond_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_bond_remote_start
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi

		if (( $? != 0 )); then
			sync_set server test_vmvf_bond_remote_end
			return 1
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		echo "test_ifaces:$iface1,$iface2"
		# disable DHCP and NetworkManager on the interface
		cat /etc/sysconfig/network-scripts/ifcfg-${iface1} | \
			sed 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' | \
			sed 's/NM_CONTROLLED=yes/NM_CONTROLLED=no/g' | \
			tee  /etc/sysconfig/network-scripts/ifcfg-${iface1}
		cat /etc/sysconfig/network-scripts/ifcfg-${iface2} | \
			sed 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' | \
			sed 's/NM_CONTROLLED=yes/NM_CONTROLLED=no/g' | \
			tee  /etc/sysconfig/network-scripts/ifcfg-${iface2}

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		if ! sriov_create_vfs ${iface1} 0 2; then
			sync_set server test_vmvf_bond_remote_end
			return 1
		fi

		if ! sriov_create_vfs ${iface2} 0 2; then
			sync_set server test_vmvf_bond_remote_end
			return 1
		fi

		ip link set ${iface1} up
		ip link set ${iface2} up

		ip link set  ${iface1} vf 0 spoofchk off
		ip link set  ${iface2} vf 1 spoofchk off
		ip link set  ${iface1} vf 0 trust on
		ip link set  ${iface2} vf 1 trust on
		ip link show
		ip addr show

		if ! sriov_attach_vf_to_vm ${iface1} 0 1 $vm1 $mac1; then
			result=1
		else
			if ! sriov_attach_vf_to_vm ${iface2} 0 2 $vm1 $mac2; then
				result=1
			else
				local cmd=(
					{export NIC_TEST1=\$\(ip link show \| grep $mac1 -B1 \| sed \'/$mac1/d\' \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST2=\$\(ip link show \| grep $mac2 -B1 \| sed \'/$mac2/d\' \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST1 down}
					{ip link set \$NIC_TEST2 down}
					{modprobe -r bonding}
					{sleep 2}
					{modprobe bonding}
					{sleep 5}
					{echo +bond1 \> /sys/class/net/bonding_masters}
					{cat /sys/class/net/bonding_masters}
					{echo active-backup \> /sys/class/net/bond1/bonding/mode}
					{echo active \> /sys/class/net/bond1/bonding/fail_over_mac}
					{echo 100 \> /sys/class/net/bond1/bonding/miimon}
					{echo +\$NIC_TEST1 \> /sys/class/net/bond1/bonding/slaves}
					{echo +\$NIC_TEST2 \> /sys/class/net/bond1/bonding/slaves}
					{ip link set bond1 up}
					{ip addr flush bond1}
					{ip addr add 172.30.${ipaddr}.11/24 dev bond1}
					{ip addr add 2021:db8:${ipaddr}::11/64 dev bond1}
					{ip link show}
					{ip addr show}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				# NIC_TEST1 and NIC_TEST2 are all up. NIC_TEST1 is active
				if ! do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file; then
					result=1
				fi

				# NIC_TEST1 is down and NIC_TEST2 is active
				local cmd=(
					{export NIC_TEST1=\$\(cat /sys/class/net/bond1/bonding/active_slave\)}
					{ip link set \$NIC_TEST1 down}
					{ip link show}
					{ip addr show}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if ! do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file; then
					result=1
				fi

				# NIC_TEST2 is down and NIC_TEST1 is active
				local cmd=(
					{export NIC_TEST2=\$\(cat /sys/class/net/bond1/bonding/active_slave\)}
					{export NIC_TEST1=\$\(cat /sys/class/net/bond1/bonding/slaves \| sed \"s/\$NIC_TEST2//\" \| sed \'s/ //\'\)}
					{ip link set \$NIC_TEST1 up}
					{ip link set \$NIC_TEST2 down}
					{ip link show}
					{ip addr show}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if ! do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file; then
					result=1
				fi

				# cleanup
				local cmd=(
					{export NIC_TEST1=\$\(ip link show \| grep bond1 \| sed \'/bond1:/d\' \| sed -n 1p \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST2=\$\(ip link show \| grep bond1 \| sed \'/bond1:/d\' \| sed -n 2p \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set bond1 down}
					{echo -\$NIC_TEST1 \> /sys/class/net/bond1/bonding/slaves}
					{echo -\$NIC_TEST2 \> /sys/class/net/bond1/bonding/slaves}
					{echo -bond1 \> /sys/class/net/bonding_masters}
					{modprobe -r bonding}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
			fi

			sriov_detach_vf_from_vm ${iface1} 0 1 $vm1
			sriov_detach_vf_from_vm ${iface2} 0 2 $vm1
		fi

		sriov_remove_vfs ${iface1} 0
		sriov_remove_vfs ${iface2} 0

		sync_set server test_vmvf_bond_remote_end
	fi

	return $result
}

sriov_test_bond_failovermac0()
{
local test_name=sriov_test_bond_failovermac0
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}
sriov_test_bond_failovermac0_vlan()
{
	local test_name=sriov_test_bond_failovermac0_vlan
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac1()
{
	local test_name=sriov_test_bond_failovermac1
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac1_pf_down()
{
	local test_name=sriov_test_bond_failovermac1_pf_down
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac1_vlan()
{
	local test_name=sriov_test_bond_failovermac1_vlan
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac2()
{
	local test_name=sriov_test_bond_failovermac2
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac2_swport_down()
{
	$dbg_flag
	local test_name=sriov_test_bond_failovermac2_swport_down
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac2_vlan()
{
	local test_name=sriov_test_bond_failovermac2_vlan
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}
sriov_test_bond_failovermac0_common() {

	log_header "sriov_test_bond_failovermac0_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		else
			rlFail "lose package more than 200"
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
				! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
				! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase sent interval
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# Increase waiting time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
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

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_failovermac0_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac0_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

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

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
		# reduce sent package interval
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
		# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0


		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_failovermac0_vlan_common() {

	log_header "sriov_test_bond_failovermac0_vlan_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip addr show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			#increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi

		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi

		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
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

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}
sriov_test_bond_failovermac0_vlan_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac0_vlan_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

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

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
	)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip addr show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi

		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_failovermac1_common() {

	log_header "sriov_test_bond_failovermac1_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
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

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac1_pf_down_common() {

	log_header "sriov_test_bond_failovermac1_pf_down_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1_pf_down

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			rlRun "ip addr add 192.100.1.1/24 dev $nic_test"
		fi
		ip addr show dev $nic_test
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test

	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$ACTIVE_SLAVE_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -eq 0 ];then
			PF_DOWN=$iface1
			PF_UP=$iface2
			echo "PF_DOWN:$PF_DOWN"
		else
			PF_DOWN=$iface2
			PF_UP=$iface1
			echo "PF_DOWN:$PF_DOWN"
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet

		vmsh run_cmd $vm1 "ping $server_ip4 -i 0.01 -c 3000 &"
		#link down the related PF
		ip link set $PF_DOWN down
		ip link show $PF_DOWN

		local cmd=(
			# increase interval time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $PF_UP
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $PF_UP
		sync_set server ${test_name}_end_feedback_result


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
			{ip addr show}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
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

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi
	return $result

}

sriov_test_bond_failovermac1_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac1_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test

	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

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

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_wait server ${test_name}_start_send_packet
			local cmd=(
				# increase interval time
				{ping $server_ip4 -i 0.01 -c 3000 \&}
				{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
				{ip link set \$ACTIVE_SLAVE down}
				# increase wait time
				{sleep 300}
				{pkill ping}
				{modprobe -rv pktgen}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			sync_set server ${test_name}_end_send_packet
			sync_wait server ${test_name}_start_feedback_result
			ip addr add 192.100.1.2/24 dev $iface1
			sleep 5
			ping 192.100.1.1 -c 5
			if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
			fi
			ip addr del 192.100.1.2/24 dev $iface1
			sync_set server ${test_name}_end_feedback_result


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac1_vlan_common() {

	log_header "sriov_test_bond_failovermac1_vlan_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else

		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
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

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}
sriov_test_bond_failovermac1_vlan_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac1_vlan_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else

		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

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

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
			sync_wait server ${test_name}_start_send_packet
			local cmd=(
				# increase interval time
				{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
				{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
				{ip link set \$ACTIVE_SLAVE down}
				# increase wait time
				{sleep 300}
				{pkill ping}
				{modprobe -rv pktgen}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			sync_set server ${test_name}_end_send_packet
			sync_wait server ${test_name}_start_feedback_result
			ip addr add 192.100.1.2/24 dev $iface1
			sleep 5
			ping 192.100.1.1 -c 5
			if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
			fi
			ip addr del 192.100.1.2/24 dev $iface1
			sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_common() {

	log_header "sriov_test_bond_failovermac2_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			echo "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
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

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_swport_down_common() {

	log_header "sriov_test_bond_failovermac2_swport_down_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2_swport_down

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi
		get_iface_sw_port $iface1 sw p1 k || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
		get_iface_sw_port $iface2 sw p2 k || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
# after add port to bond, active slave mac will change to bond mac
#		4: enp6s0: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master bond0 state UP group default qlen 1000
#    link/ether 6e:c3:95:57:2f:7e brd ff:ff:ff:ff:ff:ff permaddr 00:de:ad:23:01:01
#    5: enp11s0: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master bond0 state UP group default qlen 1000
#        link/ether 00:de:ad:23:01:02 brd ff:ff:ff:ff:ff:ff
#    6: bond0: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
#        link/ether 6e:c3:95:57:2f:7e brd ff:ff:ff:ff:ff:ff
#        inet 192.100.35.1/24 scope global bond0
#           valid_lft forever preferred_lft forever
#        inet6 2021:db02:35::1/64 scope global tentative
#           valid_lft forever preferred_lft forever
#        inet6 2001::6cc3:95ff:fe57:2f7e/64 scope global dynamic mngtmpaddr
#           valid_lft 86399sec preferred_lft 14399sec
#        inet6 fe80::6cc3:95ff:fe57:2f7e/64 scope link
#           valid_lft forever preferred_lft forever

		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST1_MAC=\$\(if ip link show \$\(cat /tmp/testiface1\) \| grep "permaddr" \;then echo \"\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "permaddr" \| awk \'\{print \$2}\'\)\" \;else echo \"\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)\" \;fi\)}
			{export NIC_TEST2_MAC=\$\(if ip link show \$\(cat /tmp/testiface2\) \| grep "permaddr" \;then echo \"\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "permaddr" \| awk \'\{print \$2}\'\)\" \;else echo \"\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)\" \;fi\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BACKUP_SLAVE \| tee /tmp/backupslave}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		#			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$ACTIVE_SLAVE_MAC = $mac1 \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -eq 0 ];then
			SW_DOWN=$p1
			PF_DOWN=$iface1
			PF_UP=$iface2
			echo "SW_DOWN:$SW_DOWN"
			echo "PF_DOWN:$PF_DOWN"
		else
			SW_DOWN=$p2
			PF_DOWN=$iface2
			PF_UP=$iface1
			echo "SW_DOWN:$SW_DOWN"
			echo "PF_DOWN:$PF_DOWN"
		fi

		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		vmsh run_cmd $vm1 "ping $server_ip4 -i 0.01 -c 3000 &"
		#link down the related SW port
		swcfg port_down $sw $SW_DOWN
		ip link show $PF_DOWN

		local cmd=(
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $PF_UP
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $PF_UP
		sync_set server ${test_name}_end_feedback_result

		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{\[ \$ACTIVE_SLAVE = \$\(cat /tmp/backupslave\) \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: active backup failed"
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
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
		swcfg port_up $sw $SW_DOWN
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac2_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

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

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(sed -n 1p /tmp/vfs\) \]\;then sed -n 2p /tmp/vfs\;else sed -n 1p /tmp/vfs\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_vlan_common() {

	log_header "sriov_test_bond_failovermac2_vlan_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
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

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=2, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"if1: \$\(cat /tmp/testiface1\) if2: \$\(cat /tmp/testiface2\) asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ "\$NIC_TEST1_MAC" = "$mac1" \] \&\& \[ "\$NIC_TEST2_MAC" = "$mac2" \] \&\& \[ "\$ACTIVE_SLAVE_MAC" = "\$BOND_MAC" \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
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

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}
sriov_test_bond_failovermac2_vlan_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac2_vlan_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
			sync_set client ${test_name}_start_send_packet
			sync_wait client ${test_name}_end_send_packet
			pkill tcpdump
			sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
			local packet_lost=$((3000-$packet_received))
			rlLog "packet_lost=$packet_lost"
			if [ $packet_lost -lt 200 ];then
					ip addr add 192.100.1.1/24 dev $nic_test
			fi
			sync_set client ${test_name}_start_feedback_result
			sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

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
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"


		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=2, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"if1: \$\(sed -n 1p /tmp/vfs\) if2: \$\(sed -n 2p /tmp/vfs\) asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ "\$NIC_TEST1_MAC" = "$mac1" \] \&\& \[ "\$NIC_TEST2_MAC" = "$mac2" \] \&\& \[ "\$ACTIVE_SLAVE_MAC" = "\$BOND_MAC" \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(sed -n 1p /tmp/vfs\) \]\;then sed -n 2p /tmp/vfs\;else sed -n 1p /tmp/vfs\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_lacp()
{
	$dbg_flag
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#don't test dualport mlx4 now
				#sriov_test_bond_lacp_mlx4en_dualport
				sriov_test_bond_lacp_common
				result=$?
			elif [ "$NIC_DRIVER" = "cxgb4" ];then
				sriov_test_bond_lacp_cxgb4
				result=$?
			else
				sriov_test_bond_lacp_common
				result=$?
			fi
		else
			sriov_test_bond_lacp_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		sriov_test_bond_lacp_common
		return $?
	fi
}

sriov_test_bond_lacp_common() {

	log_header "sriov_test_bond_lacp_common" $result_file

	local result=0
	local test_name=sriov_test_bond_lacp

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local pf_ip4="192.100.${ipaddr}.3"

	local vlan_id=3

	local server_vlanif_mac="22:22:11:11:11:10"

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		ip link set ${nic_test}.${vlan_id} address $server_vlanif_mac
		ip addr show $nic_test
		ip addr show ${nic_test}.${vlan_id}
		nic_mac=$(get_iface_mac $nic_test)
		local S_beaker_if=$(get_default_iface)
		local S_beaker_ip4=$(get_iface_ip4 $S_beaker_if)
		rlLog "nic_mac: $nic_mac"
		rlLog "Server_beaker_ip4: $S_beaker_ip4"
		sync_wait client ${test_name}_ready_to_receive_mac
		timeout 60s bash -c "until ping  ${pf_ip4} -c 5; do sleep 5; done"
		echo $nic_mac|nc ${pf_ip4} 1234
		echo $S_beaker_ip4|nc ${pf_ip4} 1235
		sync_set client ${test_name}_finish_to_receive_beaker_mac
		sync_wait client ${test_name}_done_to_receive_beaker_mac

		nc -l 1236 > /tmp/client_beaker_ip &
		sync_set client ${test_name}_ready_to_receive_beaker_ip
		sync_wait client ${test_name}_finish_to_receive_beaker_ip
		local remote_beaker_ip=$(cat /tmp/client_beaker_ip)
		echo "remote_beaker_ip: $remote_beaker_ip"
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result
		ping $remote_beaker_ip -c 5
		echo $packet_received|nc ${remote_beaker_ip} 12345
		echo "packet_received=$packet_received"
		sync_set client ${test_name}_nc12345

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local beaker_if=$(get_default_iface)
		local beaker_ip4=$(get_iface_ip4 $beaker_if)
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		ip link set $iface1 up
		ip addr add ${pf_ip4}/${ip4_mask_len} dev ${iface1}
		nc -l 1234 > /tmp/remote_mac &
		nc -l 1235 > /tmp/remote_beaker_ip &
		ip addr show $iface1
		rlLog "beaker_ip: $beaker_ip4"
		sync_set server ${test_name}_ready_to_receive_mac
		sync_wait server ${test_name}_finish_to_receive_beaker_mac
		sync_set server ${test_name}_done_to_receive_beaker_mac

		local remote_ip=$(cat /tmp/remote_beaker_ip)
		rlLog "remote_ip: $remote_ip"
		sync_wait server ${test_name}_ready_to_receive_beaker_ip
		echo $beaker_ip4|nc ${remote_ip} 1236
		sync_set server ${test_name}_finish_to_receive_beaker_ip
		sync_wait server ${test_name}_start
		remote_mac=$(cat /tmp/remote_mac)
		echo "remote_mac: $remote_mac"
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
		swcfg_port_channel $switch_name "$port_list" "active" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
		if [ -n "$kick_list" ];then
			rlLog "$kick_list are not on the same switch, kicked."
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=802.3ad miimon=100 max_bonds=1}
			{ip link set bond0 up}
			{ls -l}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
			{sleep 2}
			{cat \/proc\/net\/bonding\/bond0}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlLog "${test_name} failed:ifenslave failed";let result++; }
		fi
#    src_mac_num=$(echo $mac1 | cut -f6 -d ':')
#    dst_mac_num=$(echo $remote_mac | cut -f6 -d ':')
#    out_if_idx=$(((16#${src_mac_num} ^ 16#${dst_mac_num} ^ 16#0800) % 2))
#
#    vlan_src_mac_num=$(echo $mac1 | cut -f6 -d ':')
#    vlan_dst_mac_num=$(echo $server_vlanif_mac | cut -f6 -d ':')
#    vlan_out_if_idx=$(((16#${vlan_src_mac_num} ^ 16#${vlan_dst_mac_num} ^ 16#0800) % 2))

		local cmd=(
			{ip link set bond0 down}
			{echo layer2 \> \/sys\/class\/net\/bond0\/bonding\/xmit_hash_policy}
			{ip link set bond0 up}
			{ip link set bond0 address $mac3 }
			{cat \/proc\/net\/bonding\/bond0}
			{sleep 3}
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{timeout 120s bash -c \"until ping -c 10 $server_ip4\; do sleep 5\; done\"}
			{timeout 120s bash -c \"until ping -c 10 $server_ip6\; do sleep 5\; done\"}
			{sleep 3}
			{ip addr show}
			{ls -l}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping -c20 $server_ip4}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n | grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream1_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream1_outif=if0
			else
				let result++
				rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi

		local cmd=(
			{ip link set bond0 address $mac4}
			{cat \/proc\/net\/bonding\/bond0}
			{sleep 3}
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping $server_ip4 -c20}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n |grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream2_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream2_outif=if0
			else
				let result++
			rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi
		if [ x"${stream1_outif}" == x"${stream2_outif}" ]; then
			let result++
			rlFail "${test_name} failed: two streams dispatched to a same interface. ${stream1_outif} vs ${stream2_outif}"
		else
			rlLog "${test_name} success: two streams dispatched to different interface. ${stream1_outif} vs ${stream2_outif}"
		fi


		local cmd=(
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id address $mac5}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{cat \/proc\/net\/bonding\/bond0}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip4\; do sleep 5\; done\"}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip6\; do sleep 5\; done\"}
			{sleep 3}
			{ip addr show}
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			#{tcpdump -i \$\(cat /tmp/testiface1\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if0.cap \&}
			#{tcpdump -i \$\(cat /tmp/testiface2\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if1.cap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_vlanif_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_vlanif_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping $server_vlanif_ip4 -c20}
			{ pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n | grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream3_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream3_outif=if0
			else
				let result++
				rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi
		local cmd=(
			{ip link set bond0\.$vlan_id address $mac6}
			{cat \/proc\/net\/bonding\/bond0}
			{sleep 3}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip4\; do sleep 5\; done\"}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip6\; do sleep 5\; done\"}
			{sleep 3}
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_vlanif_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_vlanif_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping $server_vlanif_ip4 -c20}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n | grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream4_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream4_outif=if0
			else
				let result++
				rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi
		if [ x"${stream3_outif}" == x"${stream4_outif}" ]; then
			let result++
			rlFail "${test_name} failed: two streams dispatched to a same interface. ${stream3_outif} vs ${stream4_outif}"
		else
			rlLog "two streams dispatched to different interface. ${stream3_outif} vs ${stream4_outif}"
		fi

#		local cmd=(
#			{tcpdump -i \$\(cat /tmp/testiface1\) -w if0.cap \&}
#			{tcpdump -i \$\(cat /tmp/testiface2\) -w if1.cap \&}
#			{sleep 2}
#			{ping ${server_ip4} -c3}
#			{pkill tcpdump}
#			{sleep 2}
#			{ls -l \| grep if}
#		)
#		vmsh cmd_set $vm1 "${cmd[*]}"
#		if [ $? -ne 0 ];then
#			let result++
#			echo "${test_name} failed: ping failed via bond0"
#		fi
#		vmsh cmd_set $vm1 "{tcpdump -r if${out_if_idx}.cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
#		if [ $? -ne 0 ];then
#			let result++
#			echo "${test_name} failed: packet was not sent from if ${out_if_idx}"
#		fi
#		vmsh cmd_set $vm1 "{tcpdump -r if$(((${out_if_idx}+1)%2)).cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
#		if [ $? -eq 0 ];then
#			let result++
#			echo "${test_name} failed: packet was sent from wrong if"
#		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			#increase interval time
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		rlRun "ip link set $iface1 down"
		local cmd=(
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		rlLog "start nc on 12345"
		nc -l 12345 > /tmp/remote_received_packets &
		sync_set server ${test_name}_end_feedback_result
		sync_wait server ${test_name}_nc12345
		local packets_num=$(cat /tmp/remote_received_packets)
		if [ ! -n "$packets_num" ] ; then
			let result++
			rlFail "failed: no packets, or failover time is too long"
		elif [ $packets_num -lt 2800 ];then
			let result++
			rlFail "failed: failover time is too long"
		fi
		rlLog "remote_receive_packets_num $packets_num"
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after link down slave"
		fi

		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		cleanup_swcfg

		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_detach_vf_from_vm $iface2 0 2 $vm1
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0

		ip addr flush $iface1
		ip addr flush $iface2
		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_lacp_cxgb4() {

	log_header "sriov_test_bond_lacp_cxgb4" $result_file

	local result=0
	local test_name=sriov_test_bond_lacp

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local pf_ip4="192.100.${ipaddr}.3"

	local vlan_id=3

	local server_vlanif_mac="22:22:11:11:11:10"

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		ip link set ${nic_test}.${vlan_id} address $server_vlanif_mac
		ip addr show $nic_test
		ip addr show ${nic_test}.${vlan_id}
		nic_mac=$(get_iface_mac $nic_test)
		rlLog "nic_mac: $nic_mac"
		sync_wait client ${test_name}_ready_to_receive_mac
		timeout 60s bash -c "until ping  ${pf_ip4} -c 5; do sleep 5; done"
		echo $nic_mac|nc ${pf_ip4} 1234
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		ip link set $iface1 up
		ip addr add ${pf_ip4}/${ip4_mask_len} dev ${iface1}
		nc -l 1234 > /tmp/remote_mac &
		ip addr show $iface1
		sync_set server ${test_name}_ready_to_receive_mac
		sync_wait server ${test_name}_start
		remote_mac=$(cat /tmp/remote_mac)
		rlLog "remote_mac: $remote_mac"
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
		swcfg_port_channel $switch_name "$port_list" "active" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
		if [ -n "$kick_list" ];then
			rlFail "$kick_list are not on the same switch, kicked."
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=802.3ad miimon=100 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed:ifenslave failed";let result++; }
		fi
		src_mac="0x${mac1//:/}"
		dst_mac="0x${remote_mac//:/}"
		out_if_idx=$(((${src_mac}^${dst_mac}^0x0800)%2))

		vlan_src_mac="0x${mac1//:/}"
		vlan_dst_mac="0x${server_vlanif_mac//:/}"
		vlan_out_if_idx=$(((${vlan_src_mac}^${vlan_dst_mac}^0x0800)%2))

		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{sleep 50}
			{ip addr show}
			#{tcpdump -i \$\(cat /tmp/testiface1\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if0.cap \&}
			#{tcpdump -i \$\(cat /tmp/testiface2\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if1.cap \&}
			{tcpdump -i \$\(cat /tmp/testiface1\) -w if0.cap \&}
			{tcpdump -i \$\(cat /tmp/testiface2\) -w if1.cap \&}
			{sleep 2}
			{ping ${server_vlanif_ip4} -c3}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if${vlan_out_if_idx}.cap -n|grep \"${client_vlanif_ip4} > ${server_vlanif_ip4}\"}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: packet was not sent from vlan if ${vlan_out_if_idx}"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if$(((${vlan_out_if_idx}+1)%2)).cap -n|grep \"${client_vlanif_ip4} > ${server_vlanif_ip4}\"}"
		if [ $? -eq 0 ];then
			let result++
			rlFail "${test_name} failed: packet was sent from wrong vlan if"
		fi
		local cmd=(
			{tcpdump -i \$\(cat /tmp/testiface1\) -w if0.cap \&}
			{tcpdump -i \$\(cat /tmp/testiface2\) -w if1.cap \&}
			{sleep 2}
			{ping ${server_ip4} -c3}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if${out_if_idx}.cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: packet was not sent from if ${out_if_idx}"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if$(((${out_if_idx}+1)%2)).cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
		if [ $? -eq 0 ];then
			let result++
			rlFail "${test_name} failed: packet was sent from wrong if"
		fi


		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		rlRun "ip link set $iface1 down"
		local cmd=(
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface2
		timeout 60s bash -c "until ping 192.100.1.1 -c 5; do sleep 5; done"
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface2
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after link down slave"
		fi

		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		cleanup_swcfg

		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_detach_vf_from_vm $iface2 1 1 $vm1
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 1

		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}
sriov_test_bond_lacp_mlx4en_dualport() {

	log_header "sriov_test_bond_lacp_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_lacp

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local pf_ip4="192.100.${ipaddr}.3"

	local vlan_id=3

	local server_vlanif_mac="22:22:11:11:11:10"

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		ip link set ${nic_test}.${vlan_id} address $server_vlanif_mac
		ip addr show $nic_test
		ip addr show ${nic_test}.${vlan_id}
		nic_mac=$(get_iface_mac $nic_test)
		rlLog "nic_mac: $nic_mac"
		sync_wait client ${test_name}_ready_to_receive_mac
		timeout 60s bash -c "until ping  ${pf_ip4} -c 5; do sleep 5; done"
		echo $nic_mac|nc ${pf_ip4} 1234
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		ip link set $iface1 up
		ip addr add ${pf_ip4}/${ip4_mask_len} dev ${iface1}
		nc -l 1234 > /tmp/remote_mac &
		ip addr show $iface1
		sync_set server ${test_name}_ready_to_receive_mac
		sync_wait server ${test_name}_start
		remote_mac=$(cat /tmp/remote_mac)
		rlLog "remote_mac: $remote_mac"
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

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

		get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
		swcfg_port_channel $switch_name "$port_list" "active" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
		if [ -n "$kick_list" ];then
			rlLog "$kick_list are not on the same switch, kicked."
		fi

		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=802.3ad miimon=100 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed:ifenslave failed";let result++; }
		fi

		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{sleep 50}
			{ip addr show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		local cmd=(
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{ip link set \$\(sed -n 1p /tmp/vfs\) down}
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		timeout 60s bash -c "until ping 192.100.1.1 -c 5; do sleep 5; done"
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after link down slave"
		fi

		cleanup_swcfg

		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0

		ip addr flush $iface1
		ip addr flush $iface2
		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

#topo of sriov_test_vmpfbond_vmvfbond_remote
#+----------------------------------------------------+
#|                                                    |
#|   +--------+        +--------+              client |
#|   |  VM1   |        |  VM2   |                     |
#|   |        |        |vf bond |                     |
#|   +--------+        +--------+                     |
#|       |virtual       |      |                      |
#|       |port          |      |                      |
#|   +--------+         |      |                      |
#|   | bridge |       vf|      |vf                    |
#|   | virbr1 |         |      |                      |
#|   +--------+         |      |                      |
#|          |           |      +-----------------+    |
#|          |   bond    |                        |    |
#|          +-----------|-------------------+    |    |
#|           pf|        |                 pf|    |    |
#|           +-----------+               +---------+  |
#|           |     NIC   |               |   NIC   |  |
#+----------------------------------------------------+
#                |
#                |
#              server

sriov_test_vmpfbond_vmvfbond_remote()
{
	log_header "VMPFBOND_VMVFBOND <---> REMOTE" $result_file

	local result=0
	local test_name=sriov_test_vmpfbond_vmvfbond_remote

	local server_ip4="192.100.${ipaddr}.1"
	local server_ip6="2021:db02:${ipaddr}::1"
	local client1_ip4="192.100.${ipaddr}.2"
	local client1_ip6="2021:db02:${ipaddr}::2"
	local client2_ip4="192.100.${ipaddr}.3"
	local client2_ip6="2021:db02:${ipaddr}::3"
	local ip4_mask_len=24
	local ip6_mask_len=64

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test

		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end

		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_start

		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		ip link set $iface1 up
		ip link set $iface2 up
		if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
		fi

		modprobe -rv bonding
		modprobe -v bonding mode=1 fail_over_mac=1 miimon=100 max_bonds=1
		ip link set bond0 up
		ifenslave bond0 $iface1 $iface2
		#brctl addif virbr1 bond0
		ip link set dev bond0 master virbr1
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1if2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip addr flush \$NIC_TEST}
			{ip addr add $client1_ip4/$ip4_mask_len dev \$NIC_TEST}
			{ip addr add $client1_ip6/$ip6_mask_len dev \$NIC_TEST}
			{ip link show \$NIC_TEST}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm2 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 0 2 $vm2 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
		fi
		vmsh run_cmd $vm2 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm2 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm2 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm2 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{ip addr add ${client2_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client2_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"

		do_vm_netperf $vm2 $server_ip4 $server_ip6 $result_file
		result=$?
		do_vm_netperf $vm1 $server_ip4 $server_ip6 $result_file
		let result+=$?
		#do_vm_netperf $vm1 ${client2_ip4} ${client2_ip6} $result_file
		#let result+=$?

		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1if2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr flush \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm2
		sriov_detach_vf_from_vm $iface2 0 2 $vm2
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0

		#brctl delif virbr0 bond0
		ip link set dev bond0 nomaster
		modprobe -rv bonding

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

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

			vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /root/testiface1"
			vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /root/testiface2"
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

			vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /root/testiface1"
			vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'      | sed 's/://g') | tee /root/testiface2"
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
