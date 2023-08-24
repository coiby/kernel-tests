#!/bin/bash
sriov_test_bz1701191()
{
	log_header "sriov_test_bz1701191" $result_file
	local result=0
	ip link set $nic_test up
	if i_am_server;then
		sync_set client test_bz1701191_start
		sync_wait client test_bz1701191_end
	fi
	if i_am_client;then
		#if [ "$NIC_DRIVER" = "i40e" ];then
		sync_wait server test_bz1701191_start
		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1701191_end
			return 1
		fi
		pf_bus_info=$(ethtool -i $nic_test | grep 'bus-info'| sed 's/bus-info: //')
		vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
		vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')
		pf_nodedev=pci_$(echo $pf_bus_info | sed 's/[:|.]/_/g')
		vf_domain=$(echo $vf_bus_info | awk -F '[:|.]' '{print $1}')
		vf_bus=$(echo $vf_bus_info | awk -F '[:|.]' '{print $2}')
		vf_slot=$(echo $vf_bus_info | awk -F '[:|.]' '{print $3}')
		vf_function=$(echo $vf_bus_info | awk -F '[:|.]' '{print $4}')
		cat <<-EOF > ${vf_nodedev}.xml
			<interface type="hostdev" managed="no">
				<source>
					<address type='pci' domain='0x${vf_domain}' bus='0x${vf_bus}' slot='0x${vf_slot}' function='0x${vf_function}'/>
				</source>
				<mac address="00:1a:4a:16:20:81"/>
			</interface>
		EOF
		if virsh nodedev-detach $vf_nodedev && virsh attach-device $vm1 ${vf_nodedev}.xml;then
			result=0
			if [[ $ENABLE_RT_KERNEL != "yes" ]]; then
				virsh detach-device $vm1 ${vf_nodedev}.xml
			else
				local rhel_version=$( cat /etc/redhat-release | sed  's/\(.*\)\([0-9].[0-9]\)\(.*\)/\2/g')
				if [[ $(echo "${rhel_version} <= 8.6" | bc) -eq 1 ]]; then
					virsh detach-device $vm1 ${vf_nodedev}.xml
					virsh shutdown $vm1
					sleep 10
					virsh start $vm1
					sleep 10
					local vm_status=$(virsh list --all | grep $vm1 |  awk '{print $3,$4}')
					rlLog "$vm in $vm_status status"
				else
					virsh detach-device $vm1 ${vf_nodedev}.xml
				fi
			fi
			rlRun "virsh nodedev-reattach  $vf_nodedev"
		else
			rlLog "failed to attach VF to VM with managed=no"
			result=1
		fi
		rlLog "repeoducer for bz1931779: binding the PF(with a VF) driver to vfio-pci "
		rlRun "virsh nodedev-detach $pf_nodedev"
		#add more time to reproduce bug https://bugzilla.redhat.com/show_bug.cgi?id=2016618
		sleep 120
		rlRun "virsh nodedev-list | grep $pf_nodedev" "0-999"
		rlRun "virsh nodedev-reattach  $pf_nodedev" || rlRun "virsh nodedev-reset $pf_nodedev"
		rlRun "virsh nodedev-reattach  $pf_nodedev"
		sriov_remove_vfs $nic_test 0
		sync_set server test_bz1701191_end
		return $result
		#else
			#sync_wait server test_bz1701191_start
			#sync_set server test_bz1701191_end
			#echo "skip test"
		#fi
	fi
}

sriov_test_bz1392128()
{
	log_header "sriov_test_bz1392128" $result_file

	local result=0
	local test_name="sriov_test_bz1392128"
	local server_ip4="192.100.${ipaddr}.1"
	local vm1_ip4="192.100.${ipaddr}.2"
	local vm2_ip4="192.100.${ipaddr}.3"
	local server_ip6="2021:db08:${ipaddr}::1"
	local vm1_ip6="2021:db08:${ipaddr}::2"
	local vm2_ip6="2021:db08:${ipaddr}::3"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local count_vm1=0
	local count_vm2=0

	ip link set $nic_test up

	if i_am_server;then

		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		ip addr show $nic_test
		sync_set client ${test_name}_start 10800
		sync_wait client ${test_name}_end
		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_start
		#local driver=$(ethtool -i ${nic_test} | grep "driver" | awk '{print $NF}')
		#local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local total_vfs=$(sriov_get_max_vf_from_pf $nic_test 0)
		if [ $total_vfs -ge 32 ];then
			total_vfs=32
		else
			sync_set server ${test_name}_end 10800
			return 0
		fi

		if ! sriov_create_vfs $nic_test 0 $total_vfs;then
			let result++
			rlFail "${test_name} failed: create vfs failed."

		else
			local vm1_mac_perfix="00:de:ad:$(printf %02x $ipaddr):01:"
			local vm2_mac_perfix="00:de:ad:$(printf %02x $ipaddr):02:"

			local vm1_attach_vf_nums=$((total_vfs/2))

			sleep 30

			for((i=1;i<=$vm1_attach_vf_nums;i++))
			do
				local vf_mac="${vm1_mac_perfix}$(printf %02x $i)"
				if ! sriov_attach_vf_to_vm $nic_test 0 $i $vm1 ${vf_mac};then
					let result++
					rlFail "${test_name} failed: can't attach vf $i to vm1."
				else
					let count_vm1++
					rlLog "vm1 attach vf $count_vm1 times"
					rlLog "`virsh list`"
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip link set \$NIC_TEST up}
						{ip addr add ${vm1_ip4}/${ip4_mask_len} dev \$NIC_TEST}
						{ip addr add ${vm1_ip6}/${ip6_mask_len} dev \$NIC_TEST}
						{ip a}
						{ping ${server_ip4} -c3}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"

					if [ $? -ne 0 ];then
						let result++
						rlFail "ping failed via vm1 vf $i"
					fi
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip a}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					sriov_detach_vf_from_vm $nic_test 0 $i $vm1
				fi
			done
			for((i=$((vm1_attach_vf_nums+1));i<=$total_vfs;i++))
			do
				local vf_mac="${vm2_mac_perfix}$(printf %02x $i)"
				if ! sriov_attach_vf_to_vm $nic_test 0 $i $vm2 ${vf_mac};then
					let result++
					rlFail "${test_name} failed: can't attach vf $i to vm2."
				else
					let count_vm2++
					rlLog "vm2 attach vf $count_vm2 times"
					rlLog "`virsh list`"
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip link set \$NIC_TEST up}
						{ip addr add ${vm2_ip4}/${ip4_mask_len} dev \$NIC_TEST}
						{ip addr add ${vm2_ip6}/${ip6_mask_len} dev \$NIC_TEST}
						{ip a}
						{ping ${server_ip4} -c3}
					)
					vmsh cmd_set $vm2 "${cmd[*]}"
					if [ $? -ne 0 ];then
						let result++
						rlFail "ping failed via vm2 vf $i"
					fi
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip a}
					)
					vmsh cmd_set $vm2 "${cmd[*]}"
					sriov_detach_vf_from_vm $nic_test 0 $i $vm2
				fi
			done
			#for((i=1;i<=$vm1_attach_vf_nums;i++))
			#do
			#	sriov_detach_vf_from_vm $nic_test 0 $i $vm1
			#done
			#for((i=$((vm1_attach_vf_nums+1));i<=$total_vfs;i++))
			#do
			#	sriov_detach_vf_from_vm $nic_test 0 $i $vm2
			#done
			sriov_remove_vfs $nic_test 0
		fi
		sync_set server ${test_name}_end
	fi

	return $result
}

#create remove vfs 20 times
sriov_test_bz1212361()
{
	log_header "Regresssion: bz1212361" $result_file

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1212361_start
		sync_wait client test_bz1212361_end

		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_bz1212361_start

	local cx=0
	while (( $cx < 20 )); do
		sriov_create_vfs $nic_test 0 2 || { sync_set server test_bz1212361_end; return 1; }
		sleep 5
		sriov_remove_vfs $nic_test 0 || { sync_set server test_bz1212361_end; return 1; }

		let cx=cx+1
	done

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_bz1212361_end
		return 1
	fi

	local vf=$(sriov_get_vf_iface $nic_test 0 1)
	if [ -z "$vf" ]; then
		rlFail "FAIL to get VF interface"
		result=1
	else
		ethtool -i $vf

		if sriov_vfmac_is_zero $nic_test 0 1; then
			ip link set $nic_test vf 0 mac 00:de:ad:$(printf %02x $ipaddr):01:01
		fi
		ip link set $vf down
		sleep 2
		ip link set $vf up
		sleep 5
		ip addr flush $vf
		ip addr add 172.30.${ipaddr}.1/24 dev $vf
		ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
		ip -d link show $vf
		ip -d addr show $vf

		do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
		local result=$?

		ip addr flush $vf
	fi

	sriov_remove_vfs $nic_test 0 || { sync_set server test_bz1212361_end; return 1; }

	sync_set server test_bz1212361_end

	return $result
}

#mtu 9000
sriov_test_bz1145063()
{
	log_header "Regresssion: bz1145063" $result_file

	local result=0

	if i_am_server; then
		ip link set $nic_test up
		ip link set mtu 9000 dev $nic_test

		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1145063_start
		sync_wait client test_bz1145063_end

		ip link set mtu 1500 dev $nic_test
		ip addr flush $nic_test

		return 0
	fi

	sync_wait server test_bz1145063_start

	local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_bz1145063_end
		return 1
	fi

	if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
		sriov_remove_vfs $nic_test 0
		sync_set server test_bz1145063_end
		return 1
	fi

	ip link set mtu 9000 dev $nic_test

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip link set mtu 9000 \$NIC_TEST}
		{sleep 5}
		{ip addr flush \$NIC_TEST}
		{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
		{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
	result=$?

	sriov_detach_vf_from_vm $nic_test 0 1 $vm1

	sriov_remove_vfs $nic_test 0

	ip link set mtu 1500 dev $nic_test

	sync_set server test_bz1145063_end

	return $result
}


#config space
# bz1156061 also
sriov_test_bz1205903()
{
	log_header "Regresssion: bz1205903" $result_file

	local result=0

	if i_am_server; then

		sync_set client test_bz1205903
		sync_wait client test_bz1205903

		return 0
	fi

	sync_wait server test_bz1205903

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_bz1205903
		return 1
	fi

	ip link set $nic_test up

	local vf0_bus_info=$(sriov_get_vf_bus_info $nic_test 0 1)
	local vf0_pci_bus_info="pci_$(echo $vf0_bus_info | sed 's/[:|\.]/_/g')"
	virsh nodedev-detach ${vf0_pci_bus_info}

	local PREV=$(mktemp)
	local CUR=$(mktemp)

	local d1=$(date +"%s")
	lspci -xxx -s ${vf0_bus_info} > $PREV
	cat $PREV
	while (true); do
		lspci -xxx -s $vf0_bus_info > $CUR
		if ! diff -q $PREV $CUR > /dev/null; then
			diff -U 0 $PREV $CUR
			cp $CUR $PREV
			result=1
		fi
		local d2=$(date +"%s");
		if (( $d2 - $d1 > 300 )); then
			break
		fi
	done

	sriov_remove_vfs $nic_test 0

	sync_set server test_bz1205903

	return $result
}

sriov_test_bz1794812_excessive_interrupts()
{
	log_header "excessive interrupts in hypervisor due to get link settings" $result_file

	local result=0

	if i_am_server; then

		sync_set client test_bz1794812
		sync_wait client test_bz1794812

		return 0
	fi
	if i_am_client;then
		if [ "$NIC_DRIVER" = "ixgbe" ];then
			sync_wait server test_bz1794812
			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_bz1794812
				return 1
			fi
			#get the cpu core num
			cpu_cores=$(cat /proc/cpuinfo |grep "processor"|wc -l)
			#get interrupt
			get_interrupts()
			{
				local $1
				let num_c=cpu_cores+1
				for i in `seq 2 $num_c`
				do
					interruputs_pf=$(grep $nic_test /proc/interrupts|grep -v "TxRx"|awk '{print $'$i'}')
					[ ! -z "$interruputs_pf" ] && let interruputs_sum_pf+=$interruputs_pf
					echo $interruputs_sum_pf > interruputs_sum_pf_$1.log
				done
					echo interruputs_sum_pf_$1
					cat interruputs_sum_pf_$1.log
			}
			check_interrupts_increase()
			{
				after=$(cat interruputs_sum_pf_after.log)
				before=$(cat interruputs_sum_pf_before.log)
				let interrupts_increase=after-before
				rlAssertGreaterOrEqual "500 >= $interrupts_increase ?" 500 $interrupts_increase
			}
			run_ethtool()
			{
				local $1
				for i in `seq 0 1000`
				do
					ethtool $1
				done
			}

			ip link set $nic_test up
			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			if [ -z "$vf" ]; then
				rlFail "FAIL to get VF interface"
				result=1
			else
				rlLog "get pf interrupts before running ethtool in loop"
				get_interrupts before
				rlLog "run ethtool in loop"
				run_ethtool $vf > /dev/null
				rlLog "get pf interrupts after running ethtool in loop"
				get_interrupts after
				rlLog "check interrupts increase"
				check_interrupts_increase
			fi
			sriov_remove_vfs $nic_test 0
			sync_set server test_bz1794812
			return $result
		else
			sync_wait server test_bz1794812
			sync_set server test_bz1794812
		fi
	fi
}

#reproducer for bz2041318
sriov_test_vf_trust_broadcast()
{
	$dbg_flag
	log_header "VF <---> REMOTE" $result_file

	local result=0
	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test

		sync_set client test_vf_trust_start
		sync_wait client test_vf_trust_ready_send_packet
		local pkt="Ether(src='00:01:02:03:04:05', dst='ff:ff:ff:ff:ff:ff')/Dot1Q(vlan=32)/ARP(hwsrc='00:01:02:03:04:05' , pdst='1.2.3.4')"
		if [ $(GetDistroRelease) = 8 ];then
			/usr/libexec/platform-python -c  "from scapy.all import *; sendp($pkt, iface='$nic_test', count=10 )"
		else
			python -c  "from scapy.all import *; sendp($pkt, iface='$nic_test', count=10 )"
		fi
		sync_set client test_vf_trust_ready_send_packet
		sync_wait client test_vf_trust_end

		ip addr flush $nic_test
	else
		sync_wait server test_vf_remote_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_trust_ready_send_packet
			sync_wait server test_vf_trust_ready_send_packet
			sync_set server test_vf_trust_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			echo "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf
			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
				#workaround for ionic bz1914175
				ip link set dev $vf address 00:de:ad:$(printf "%02x" $ipaddr):01:01
				ip link set $vf down
				sleep 2
			fi
			ip link set $vf up
			sleep 5
			ip link set $nic_test vf 0 trust on spoof off
			ip link show $nic_test
			ip addr flush $vf
			ip addr add 172.30.${ipaddr}.11/24 dev $vf
			ip addr show $vf
			ping -c5 172.30.${ipaddr}.2
			#check the broadcast with trust off spoof on
			rlRun "tcpdump -i $vf -e vlan and arp -w vlan_broadcast.pcap &"
			rlRun "tcpdump -i $nic_test -e vlan and arp -w pf_vlan_broadcast.pcap &"
			sync_set server test_vf_trust_ready_send_packet
			sync_wait server test_vf_trust_ready_send_packet
			pkill tcpdump
			sleep 5
			rlLog "check the vf whether receive the broadcast"
			tcpdump -r vlan_broadcast.pcap -enn | grep -i 'vlan 32'
			local result=$?
			rlLog "check the pf whether receive the broadcast"
			tcpdump -r pf_vlan_broadcast.pcap -enn | grep -i 'vlan 32'

		fi
		sriov_remove_vfs $nic_test 0
		rm *_broadcast.pcap

		sync_set server test_vf_remote_end
	fi

	return $result
}

#
# buffer overflow and/or deadlock when VF has more than 32 multicast
#
sriov_test_bz1445814()
{
	log_header "sriov_test_bz1445814" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1445814_start
		sync_wait client test_bz1445814_end

		ip addr flush $nic_test
	else
		sync_wait server test_bz1445814_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1445814_end
			return 1
		fi

		vf_name=$(sriov_get_vf_iface $nic_test 0 1)
		for i in $(seq 2 50); do
			a="33:33:00:00:00:$(printf "%02x" $i)"
			rlLog $a
			ip ma add $a dev $vf_name
			if [ $? -ne 0 ];then
				let result+=1
				rlFail "failed: add ma $a error"
			fi
		done

		sriov_remove_vfs $nic_test 0

		sync_set server test_bz1445814_end
	fi

	return $result
}

# guest VM unable to communicate when VFs are defined on hosts PF
#
sriov_test_bz1493953()
{
	log_header "sriov_test_bz1493953" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1493953_start
		sync_wait client test_bz1493953_end

		ip addr flush $nic_test
	else
		sync_wait server test_bz1493953_start

		ip link add br0 type bridge
		ip link set br0 up
		#get the corresponding vnet port
		#vnetport=$(ip link show | grep vnet | grep virbr0 | awk '{ print $2 }' | sed 's/://g' | head -n1)
		rlLog "virsh dumpxml ${vm1}| grep -C 5 ${mac4vm1} | grep vnet | awk -F \"dev='\" '{print $2}' | sed \"s/'\/>//g\""
		vnetport=$(virsh dumpxml ${vm1}| grep -C 5 ${mac4vm1} | grep vnet | awk -F "dev='" '{print $2}' | sed "s/'\/>//g")
		rlLog "vnet $vnetport"
		if (($rhel_version <= 6)); then
			#brctl delif virbr0 vnet0
			#brctl addif br0 vnet0
			#brctl addif br0 $nic_test
			ip link set dev $vnetport nomaster
			ip link set dev $vnetport master br0
			ip link set dev $nic_test master br0
		else
			ip link set $nic_test master br0
			ip link set $vnetport master br0
			ip link show
		fi

		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1493953_end
			ip link del br0
			return 1
		fi

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
			{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		local cmd=(
			{timeout 60s bash -c \"until ping -c3 172.30.${ipaddr}.2\; do sleep 5\; done\"}
			{timeout 60s bash -c \"until ping6 -c3 2021:db8:${ipaddr}::2\; do sleep 5\; done\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		result=$?

		if (($rhel_version <= 6)); then
			#brctl delif br0 vnet0
			#brctl addif br0 virbr0
			#brctl delif br0 $nic_test
			ip link set dev $vnetport nomaster
			ip link set dev $vnetport master virbr0
			ip link set dev $nic_test nomaster

		else
			ip link set $vnetport master virbr0
			ip link set $nic_test nomaster
		fi
		ip link del br0
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr del 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
			{ip addr del 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_remove_vfs $nic_test 0

		sync_set server test_bz1493953_end
	fi

	return $result
}

#
#  ixgbevf takes a long time to update net.ipv6.conf.all.forwarding=1
#
sriov_test_bz1483396()
{
	log_header "sriov_test_bz1483396" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		sync_set client test_bz1483396_start
		sync_wait client test_bz1483396_end
	else
		sync_wait server test_bz1483396_start

		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1483396_end
			ip link del br0
			return 1
		fi
		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		ip link set $vf down
		ip link set $vf name vf0
		ip link set vf0 up
		ip link add link vf0 name vf0.100 type vlan proto 802.1ad id 100
		ip link set dev vf0.100 up
		for NUM in {1..2048}; do
			ip link add link vf0.100 name vf0.100.$NUM type vlan proto 802.1q id $NUM
			ip link set dev vf0.100.$NUM up
		done
		#will chech dmesg with param "--param=SET_DMESG_CHECK_KEY=yes" for every Task testing
		#dmesg -C;dmesg -c
		time sysctl -w net.ipv6.conf.all.forwarding=1
		dmesg|grep "BUG: soft lockup" && { result=1; rlFail "failed:soft lockup occur"; }
		#dmesg -C;dmesg -c
		time sysctl -w net.ipv6.conf.all.forwarding=0
		dmesg|grep "BUG: soft lockup" && { result=1; rlFail "failed:soft lockup occur"; }

		ip link del vf0.100
		sriov_remove_vfs $nic_test 0

		sync_set server test_bz1483396_end
		fi

	return $result
}

sriov_test_switchdev_bz1870593()
{
	log_header "bz1870593" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_switchdev_1870593_start
		sync_wait client test_switchdev_1870593_end

		ip addr flush $nic_test
	else
		#sync_wait server test_switchdev_1870593_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]] || [[ "$NIC_DRIVER" == "ice" ]];then
			switchdev_setup_nfp
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
			ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi
			sync_wait server test_switchdev_1870593_start

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_switchdev_1870593_end
				return 1
			fi

			switchdev_setup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)

			#check the vm state, re-start it if not running
			g1_state=$(virsh list --all | grep g1 | awk '{print $3}')
			if [ x"$g1_state" != x"running" ]
			then
				virsh start g1
				sleep 10
			fi

			local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local reps=$(switchdev_get_reps $nic_test)
			if [ -z "$reps" ]; then
				rlFail "FAILED to get representor"
				result=1
			else
				ip link set $nic_test master hostbr0
				rlLog "rep list $reps"
				for rep in $reps
				do
					ip link show $rep
					ip link set $rep up
					ip link set $rep master hostbr0
					rlRun "nmcli device set $rep managed no"
				done
				ip link set $vf up
				sleep 5
				ip link show
			fi

			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
				result=1
			else
				local cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST up}
					{ip addr flush \$NIC_TEST}
					{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
					{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
					{ip link show \$NIC_TEST}
					{ip addr show \$NIC_TEST}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				#check the packet stats before running netperf
				rlLog "rep list $reps"
				for rep in $reps
				do
					rlRun "ip -s link show $rep "
					count_link1_before=`ip -s link show $rep | awk  'NR==4' | awk '{print $2}'`
				done
				vmsh run_cmd $vm1 "timeout 40s bash -c \"until ping -c10 172.30.${ipaddr}.2; do sleep 5; done\""
				result=$?
				for rep in $reps
				do
					rlRun "ip -s link show $rep"
					count_link1_after=`ip -s link show $rep | awk  'NR==4' | awk '{print $2}'`
				done
				rlAssertGreater "packets_after lager than packets_before" $count_link1_after $count_link1_before

			fi

			#clean up
			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			switchdev_cleanup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0

			sync_set server test_switchdev_1870593_end
		else
			sync_wait server test_switchdev_1870593_start
			sync_set server test_switchdev_1870593_end
		fi
	fi

	return $result
}

sriov_test_vf_not_created_bz1875338()
{
	log_header "1875338" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_1875338_start 30000
		sync_wait client test_1875338_end 30000

		ip addr flush $nic_test
	else
		sync_wait server test_1875338_start 30000
		local vf_num=5
		for ((i=0; i<1000; i++)); do
			sleep 1
			rlLog "--- test $i ---"
			echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
			echo $vf_num > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
			rlRun "vfs_virtfn=$(ls /sys/class/net/$nic_test/device/ | grep virtfn | wc -l)"
			if [[ $vfs_virtfn != "${vf_num}" ]]; then
				rlFail "FAIL to create VF func"
				ls /sys/class/net/$nic_test/device/
				echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
				sync_set server test_1875338_end 30000
				return 1
			fi
			rlRun "VFS=$(ip link show ${nic_test} 2>/dev/null | grep "vf" | wc -l)"
			if [[ $VFS != "${vf_num}" ]]; then
				ip link show dev $nic_test
				ls /sys/class/net/$nic_test/device/
				rlFail "FAIL to create VFs"
				echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
				sync_set server test_1875338_end 30000
				result=1
				return 1
			fi
		done
		sriov_remove_vfs $nic_test 0
		sync_set server test_1875338_end 30000
	fi
	return $result
}

sriov_test_vf_iface_not_created()
{
	log_header "vf_iface_not_created" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vf_iface_not_created_start 30000
		sync_wait client test_vf_iface_not_created_end 30000

		ip addr flush $nic_test
	else
		sync_wait server test_vf_iface_not_created_start 30000
		#get vf interface pattern
		echo 1 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
		vf=$(sriov_get_vf_iface $nic_test 0 1)
		vf_if_pattern=${vf%*${vf:(-1)}}
		rlLog "===============vf interface pattern: $vf_if_pattern================"
		echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
		#begin to test
		local vf_num=5
		for ((i=0; i<1000; i++)); do
			sleep 1
			rlLog "--- test $i ---"
			echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
			echo $vf_num > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
			rlRun "vfs_virtfn=$(ls /sys/class/net/$nic_test/device/ | grep virtfn | wc -l)"
			if [[ $vfs_virtfn != "${vf_num}" ]]; then
				rlFail "FAIL to create VF func"
				ls /sys/class/net/$nic_test/device/
				echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
				sync_set server test_vf_iface_not_created_end 30000
				return 1
			fi
			rlRun "VF_IFACES=$(ip link show  2>/dev/null | grep ${vf_if_pattern}  | wc -l)"
			if [[ $VF_IFACES != "${vf_num}" ]]; then
				sleep 5
				ip link show
				ls /sys/class/net/$nic_test/device/
				rlRun "VF_IFACES=$(ip link show  2>/dev/null | grep ${vf_if_pattern}  | wc -l)"
				if [[ $VF_IFACES != "${vf_num}" ]]; then
					ls /sys/class/net/$nic_test/device/
					ip link show
					echo "sleep 5 and check the iface again"
					sleep 5
					ip link show
					rlFail "FAIL to get VF interface"
					echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs 2>/dev/null
					sync_set server test_vf_iface_not_created_end 30000
					result=1
					return 1
				fi
			fi
		done
		sriov_remove_vfs $nic_test 0
		sync_set server test_vf_iface_not_created_end 30000
	fi
	return $result
}

#reproducer for bz1842896
sriov_test_vmvf_hibernation()
{
	log_header "sriov_test_vmvf_hibernation" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vmvf_hibernation_start
		sync_wait client test_vmvf_hibernation_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_hibernation_start
		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_hibernation_end
			return 1
		fi
# need use pre-define to test this case. here is the refer to https://bugzilla.redhat.com/show_bug.cgi?id=2024503#c16
#- the root cause is that the management of the device was not passed to the vfio-pci driver (the unbind on iavf and bind to vfio-pci was not performed on host); I compared the dmesg outputs of persistent configuration in the domain XML vs hot-plugging.
#- vfio-pci did not enable the pci device for the virtual machine;
#
#Probably the device even though setup as managed='yes' in the xml file will/might not be handled properly by libvirt because the interface was hot-plugged and in the documentation (https://libvirt.org/html/libvirt-libvirt-domain.html) is stated:
#
#"Be aware that hotplug changes might not persist across a domain going into S4 state (also known as hibernation) unless you also modify the persistent domain definition."
#
#Which means that the device should be defined in the domain XML in order to be restored properly by the libvirt.
#
#So the VF interface is still managed by the host and not by the VM because the libvirt failed to enable it for the VM.
		local vf_interface=$(sriov_get_vf_iface $nic_test 0 1)
		local vf_businfo=$(ethtool -i $vf_interface | sed -n '/bus-info: / s/bus-info: //p')
		which virt-xml || yum install -y virt-install
		virt-xml $vm1 --add-device --hostdev $vf_businfo --print-diff
		virt-xml $vm1 --add-device --hostdev $vf_businfo
		virsh shutdown $vm1
		sleep 60
		virsh start $vm1
		sleep 60
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip link show \$NIC_TEST}
			{rm -rf \/var\/crash/\*}
			{systemctl hibernate}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if virsh list --all | grep $vm1 | grep -v "running"; then
			rlRun "virsh start $vm1"
		fi
		rlRun "virsh list --all"
		# check no vmcore file on guest
		local cmd=(
			{export vmcore=\$\(ls \/var\/crash \| wc -l\)}
			{test 0 = \$vmcore}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? != 0 ]; then
			rlFail "vmcore file on guest, please check it!!!"
		else
			rlLog "no vmcore file on guest"
		fi
		virt-xml $vm1 --remove-device --hostdev $vf_businfo --print-diff
		virt-xml $vm1 --remove-device --hostdev $vf_businfo
		virsh shutdown $vm1
		sleep 60
		virsh start $vm1
		sleep 60
		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_hibernation_end
	fi
	return $result
}

sriov_test_vf_mac_switchdev_bz1814350()
{
	log_header "VF MAC <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vf_mac_remote_switchdev_start
		sync_wait client test_vf_mac_remote_switchdev_end

		ip addr flush $nic_test
	else
		sync_wait server test_vf_mac_remote_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]] || [[ "$NIC_DRIVER" == "ice" ]];then
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
			ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_vf_mac_remote_switchdev_end
				return 1
			fi

			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local mac=00:de:ad:$(printf "%02x" $ipaddr):01:01
			if [ -z "$vf" ]; then
				rlFail "FAILED to get VF interface"
				result=1
			else
				ethtool -i $vf
				rlLog "setting the vf mac via ip link set $nic_test vf 0 mac $mac"
				ip link set $nic_test vf 0 mac $mac
				rlLog "checking the vf mac"
				local mac_g="$(ip link show $nic_test | grep "vf 0" | awk '{ print $4 }')"
				if [ "$mac_g" != "$mac" ]; then
					rlFail "FAILED to change vf mac"
					result=1
				else
					rlLog "change the sriov mode to switchdev"
					switchdev_setup_mlx
					#workaround for bz1877274
					nic_test=$(get_required_iface)
					ip link set $nic_test up
					sleep 2
					ip link show $nic_test

					local reps=$(switchdev_get_reps $nic_test)
					if [ -z "$reps" ]; then
						rlFail "FAILED to get representor"
						result=1
					else
						rlLog "checking the vf mac with switchdev mode"
						local mac_g1="$(ip link show $nic_test | grep "vf 0" | awk '{ print $4 }')"
						if [ "$mac_g1" != "$mac" ]; then
							rlFail "FAILED: the vf mac reset after moving to switchdev mode"
							result=1
						else
							rlLog "PASS: the vf mac does not reset after moving to switchdev mode"
							ip link set $nic_test master hostbr0
							rlLog "rep list $reps"
							for rep in $reps
							do
								ip link show $rep
								ip link set $rep up
								ip link set $rep master hostbr0
								rlRun "nmcli device set $rep managed no"
							done
							ip link set $vf up
							sleep 5
							ip link show
							ip addr flush $vf
							ip addr add 172.30.${ipaddr}.1/24 dev $vf
							ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
							ip -d link show $vf
							ip -d addr show $vf

							do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
							local result=$?

							ip addr flush $vf
						fi
					fi
				fi
			fi

			#clean up
			switchdev_cleanup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0

			sync_set server test_vf_mac_remote_switchdev_end
		else
			sync_set server test_vf_mac_remote_switchdev_end
		fi
	fi

	return $result
}

sriov_test_pf_steering_switchdev_bz1856660()
{
	log_header "PF STEERING <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_pf_str_remote_switchdev_start
		sync_wait client test_pf_str_remote_switchdev_end

		ip addr flush $nic_test
	else
		sync_wait server test_pf_str_remote_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_pf_str_remote_switchdev_end
				return 1
			fi

			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local mac=00:de:ad:$(printf "%02x" $ipaddr):01:01
			if [ -z "$vf" ]; then
				rlFail "FAILED to get VF interface"
				result=1
			else
				switchdev_setup_mlx
				#workaround for bz1877274
				nic_test=$(get_required_iface)

				# add steering rules
				ip link set $nic_test up
				sleep 2
				ip link show $nic_test
				ip addr flush $nic_test
				ip addr add 172.30.${ipaddr}.11/24 dev $nic_test
				ping 172.30.${ipaddr}.2 -c 3
				sleep 3
				ethtool -L $nic_test combined 8
				ethtool -X $nic_test equal 6
				ethtool -U $nic_test flow-type ip4 src-ip 172.30.${ipaddr}.2 action 7 loc 1
				ip addr show $nic_test
				ethtool -u $nic_test
				ethtool -S $nic_test | grep rx7_by
				count1_before=`ethtool -S $nic_test | grep rx7_by | awk '{print $NF}'`
				ping 172.30.${ipaddr}.2 -c 10
				ethtool -S $nic_test | grep rx7_by
				count1_after=`ethtool -S $nic_test | grep rx7_by | awk '{print $NF}'`
				rlAssertGreater "packets_after lager than packets_before" $count1_after $count1_before

				switchdev_cleanup_mlx
				#workaround for bz1877274
				nic_test=$(get_required_iface)

				count2_before=`ethtool -S $nic_test | grep rx7_by | awk '{print $2}'`
				ping 172.30.${ipaddr}.2 -c 10
				count2_after=`ethtool -S $nic_test | grep rx7_by | awk '{print $2}'`
				rlAssertEquals "packets_after should equal packets_before" $count2_after $count2_before

			fi

			sriov_remove_vfs $nic_test 0
			delete_all_rules()
			{
				local dev=$1
				local rule_sum=$(ethtool -u $dev | grep -e "Total [0-9]* rules" | awk '{print $2}')
				if [ x"$rule_sum" == x"0" ];then
					return 0
				fi
				local rule_ids=$(ethtool -u $dev | grep Filter | awk '{print $2}')
				for rule in $rule_ids;do
					ethtool -U $dev delete $rule
				done
				return 0
			}

			delete_all_rules $nic_test
			ip addr flush $nic_test
			sync_set server test_pf_str_remote_switchdev_end
		else
			sync_set server test_pf_str_remote_switchdev_end
		fi
	fi

	return $result
}

#refer to bug https://bugzilla.redhat.com/show_bug.cgi?id=2088787
sriov_test_podcnts_vfs_remote_bz2088787()
{
	log_header "POD_CNTVF1<---> REMOTE" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip link add link ${nic_test} name ${nic_test}.5 type vlan id 5
		ip link set $nic_test.5 up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test.5
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test.5
		rlRun "iperf3_install"
		rlRun "iperf3 -s -p 50001 -V --logfile ./serverlog &"
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end
		ip addr flush $nic_test.5
		return 0
	fi

	sync_wait server test_podcntvf1_podcntvf2_start

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
		echo "$test_name get required_iface failed."
		sync_set server ${test_name}_end
		return 1
	fi
	iface1=$(echo $test_iface | awk '{print $1}')
	iface2=$(echo $test_iface | awk '{print $2}')
	echo "test_ifaces:$iface1,$iface2"

	local vid=3
	local mac1="00:de:a1:$(printf %02x $ipaddr):11:01"
	local mac2="00:de:a1:$(printf %02x $ipaddr):12:01"

	if ! sriov_create_vfs $iface1 0 4 || ! sriov_create_vfs $iface2 0 4; then
		rlLog "${test_name} failed:create vfs failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi
	sriov_setup_pod_container

	ip link set $iface1 up
	ip link set $iface2 up
	for i in `seq 1 4`
	do
		local pf1vf=$(sriov_get_vf_iface $iface1 0 $i)
		ip link set $pf1vf up
		sleep 2
	done
	local pf2vf1=$(sriov_get_vf_iface $iface2 0 1)
	local pf2vf2=$(sriov_get_vf_iface $iface2 0 2)
	ip link set $pf2vf1 up
	ip link set $pf2vf2 up

	ip link set ${iface2} vf 0 spoofchk off trust on
	ip link set ${iface2} vf 1 spoofchk off trust on
	ip link set ${iface2} vf 0 vlan 5
	ip link set ${iface2} vf 1 vlan 5
	ip link set ${iface1} vf 0 vlan 51
	ip link set ${iface1} vf 0 spoofchk on trust off
	ip link set ${iface1} vf 1 vlan 52
	ip link set ${iface1} vf 1 spoofchk off trust on
	ip link set ${iface1} vf 2 vlan 51
	ip link set ${iface1} vf 2 spoofchk on trust off
	ip link set ${iface1} vf 3 vlan 52
	ip link set ${iface1} vf 3 spoofchk off trust on


	if ! sriov_attach_vf_to_cnt $iface1 0 1 $container1; then
		rlLog 'failed to attach vf to container1'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface1 0 2 $container2; then
		rlLog 'failed to attach vf to container2'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface1 0 3 $container3; then
		rlLog 'failed to attach vf to container3'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface1 0 4 $container4; then
		rlLog 'failed to attach vf to container4'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi

	if ! sriov_attach_vf_to_cnt $iface2 0 1 $container1; then
		rlLog 'failed to attach vf to container1'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface2 0 2 $container3; then
		rlLog 'failed to attach vf to container3'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi

	# setup pod1 cntvf
	podman exec $container1 ip addr flush $pf2vf1
	podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $pf2vf1
	podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $pf2vf1
	podman exec $container1 ip link show $pf2vf1
	podman exec $container1 ip addr show $pf2vf1

	# setup pod2 cntvf
	podman exec $container3 ip addr flush $pf2vf2
	podman exec $container3 ip addr add 172.30.${ipaddr}.21/24 dev $pf2vf2
	podman exec $container3 ip addr add 2021:db8:${ipaddr}::21/64 dev $pf2vf2
	podman exec $container4 ip link show $pf2vf2
	podman exec $container3 ip addr show $pf2vf2
	# test
	local result=0
	rlRun "podman exec $container1 ping 172.30.${ipaddr}.1 -c 5"
	rlRun "podman exec $container1 ping6 2021:db8:${ipaddr}::1 -c 5"
	rlRun "podman exec $container3 ping 172.30.${ipaddr}.1 -c 5"
	rlRun "podman exec $container3 ping6 2021:db8:${ipaddr}::1 -c 5"
	rlRun "podman exec $container1 iperf3 -c 172.30.${ipaddr}.1 -p 50001"
	rlRun "podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::1 -p 50001"

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $iface1 0
	sriov_remove_vfs $iface2 0

	NIC_NUM=$OLD_NIC_NUM
	NIC_DRIVER=$OLD_NIC_DRIVER
	NIC_MODEL=$OLD_NIC_MODEL
	NIC_SPEED=$OLD_NIC_SPEED

	sync_set server ${test_name}_end

	return $result
}

sriov_test_delete_vm_with_kernel_args()
{
	# reproduce for bug https://bugzilla.redhat.com/show_bug.cgi?id=1835705
	rlLog "Start sriov_test_delete_vm_with_kernel_args"
	if i_am_server; then
		sync_set client test_delete_vm_with_kernel_args_start 14400
		sync_wait client test_delete_vm_with_kernel_args_end 14400
		return 0
	else
		# install python environment
		/usr/bin/python3 -V &>/dev/null || yum -y install python3
		[[ -f /usr/bin/python ]] || ln -s $(which python3) /usr/bin/python
		which pip &>/dev/null || which pip3 &>/dev/null || yum install -y python3-pip
		which pip &>/dev/null || ln -s $(which pip3) /usr/bin/pip
		lsmod | grep vfio_pci || modprobe vfio_pci
		# got isolate cpu expect cpu0 and cpu0's sibiling cores, but need nosmt effect after change grub file.
		if [ "$SYS_ARCH" == "ppc64le" ];then
			local numa=$(get_info.sh nic_numa_node $nic_test)
			local isolate_cores=$(get_info.sh isolated_cores $numa)
		else
			local isolate_cores=$(get_cpu.py --bug_reproduce_1835705)
		fi
		if [ -f /tmp/reboot_num ] && [[ $(cat /tmp/reboot_num) == "1" ]]; then
			if (grep "default_hugepagesz" /proc/cmdline &>/dev/null || \
				grep "hugepagesz" /proc/cmdline &>/dev/null || \
				grep "hugepages" /proc/cmdline &>/dev/null || \
				grep "isolate_cores=${isolate_cores}" /proc/cmdline &>/dev/null)
			then
				rlLog "tunning success"
				sync_wait server test_delete_vm_with_kernel_args_start 14400
			else
				rlFail "modify grub failed"
				sync_set server test_delete_vm_with_kernel_args_end 14400
			fi
		else
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz" /proc/cmdline &>/dev/null || \
			! grep "hugepages" /proc/cmdline &>/dev/null)
			then
				setup_bootopts.sh \
				--hugepagesz=2G \
				--hugepages=12 \
				--isolated_cores="$isolate_cores" \
				--extra="intel_idle.max_cstate=0 processor.max_cstate=0 intel_pstate=disable" \
				--tuned-profiles=cpu-partitioning
				echo "1" > /tmp/reboot_num
				reboot
				sleep 300
			elif [ "$SYS_ARCH" != "ppc64le" ] && [ ! -f /tmp/reboot_num ] && (\
			! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null || \
			! grep "nosmt=force" /proc/cmdline &>/dev/null || \
			! grep "isolate_cores=${isolate_cores}" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt nosmt=force" --update-kernel=$(grubby --default-kernel)
				isolate_cores=$(get_cpu.py --bug_reproduce_1835705)
				rlLog "isolate core are ${isolate_cores}"
				# do cpu tunning on host
				if ! uname -r | grep rt; then
					rpm -q tuned-profiles-cpu-partitioning || yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
					echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
					tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
				elif uname -r | grep rt; then
					rpm -q tuned-profiles-nfv || yum install -y tuned tuned-profiles-nfv &>/dev/null
					echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
					echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
					tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
					systemctl disable irqbalance
					systemctl stop irqbalance
				fi
				rlLog "finish cpu tuning"
				# set reboot flag to tmp file
				echo "1" > /tmp/reboot_num
				reboot
				sleep 300
			fi
		fi

		# start test
		if [ -f /tmp/reboot_num ] && [[ $(cat /tmp/reboot_num) == "1" ]]; then
			ip link show | grep virbr1 || ip link add name virbr1 type bridge
			ip link set virbr1 up

			rlLog "Create image folder"
			[ -f /home/sriov_test_delete_vm_with_kernel_args/images ] || mkdir -p /home/sriov_test_delete_vm_with_kernel_args/images


			# ensure default network start as well
			if ! virsh net-list | grep default &&
			! virsh net-start default;then
				virsh net-define /usr/share/libvirt/networks/default.xml
				virsh net-start default
				virsh net-autostart default
			fi

			local vm_num=6
			local vm_mac_perfix="00:de:aa:05:01:"

			#install VMs
			for((i=1;i<=$vm_num;i++))
			do
				local vmname=test_bug1835705_vm$i

				if virsh list --name | grep -w "$vmname" ||
					virsh start $vmname;then
					continue
				else
					rlLog "Download guest image..."
					pushd "/home/sriov_test_delete_vm_with_kernel_args/images/" 1>/dev/null
					[ -f test_bug1835705_vm$i.qcow2 ] || wget -nv $IMG_GUEST -O test_bug1835705_vm$i.qcow2
					chmod -R 777 test_bug1835705_vm$i.qcow2

					if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
					virt-copy-in -a test_bug1835705_vm$i.qcow2 ${CASE_PATH}/../../common/tools/brewkoji_install.sh /root
					fi
					popd

					rlLog "Creating guest $vmname..."
					virt-install \
					--name $vmname \
					--vcpus=1 \
					--ram=1024 \
					--disk path=/home/sriov_test_delete_vm_with_kernel_args/images/test_bug1835705_vm$i.qcow2,device=disk,bus=virtio,format=qcow2 \
					--network bridge=virbr0,model=virtio,mac=${vm_mac_perfix}$(printf %02x $i) \
					--import --boot hd \
					--accelerate \
					--graphics vnc,listen=0.0.0.0 \
					--force \
					--os-variant=rhel-unknown \
					--noautoconsol
				fi
				# wait VM bootup
				sleep 60
			done

			# test 20 times create vf/ attach to vm and detach
			for ((h=1;h<=20;h++)); do
				rlLog "start $h tests"
				if ! sriov_create_vfs $nic_test 0 $vm_num; then
					rlFail "ceate VF failed"
				fi
				sleep 5
				for ((i=0;i<=$(expr $vm_num - 1);i++))
				do
					ip link set $nic_test vf $i vlan 3
					sleep 5
				done

				for ((i=1;i<=$vm_num;i++))
				do
					local vf_interface_name=$(sriov_get_vf_iface $nic_test 0 $i)
					ip addr flush ${vf_interface_name}
					sleep 1
				done

				local vm_test_vf_prefix="00:de:ad:02:01:"
				local pf_bus_info=$(ethtool -i $nic_test | grep 'bus-info' | sed 's/bus-info: //')
				local vf_bus_info=($(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///'))

				declare -A vf_dict
				for((i=0;i<=$(expr $vm_num - 1);i++)); do
					vf_dict[$[i]]=${vf_bus_info[i]}
				done

				for j in "${!vf_dict[@]}"
				do
					virsh attach-interface --domain test_bug1835705_vm$(expr $j + 1) --type hostdev --source ${vf_dict[$j]} --mac ${vm_test_vf_prefix}$(printf %02x $j) --managed --live || rlFail "attach device failed"
				done

				for((k=1;k<=$vm_num;k++))
				do
					virsh detach-interface --domain test_bug1835705_vm$k --type hostdev --mac ${vm_test_vf_prefix}$(printf %02x $(expr $k - 1))  || rlFail "detach device failed"
					virsh reboot test_bug1835705_vm$k
				done

				for ((k=1;k<=$vm_num;k++))
				do
					vmsh run_cmd test_bug1835705_vm$k "ip link show"
				done

				sriov_remove_vfs $nic_test
				rlLog "finish $h tests"
			done
			# clean temp guests
			for ((h=1; h<$vm_num;h++))
			do
				virsh destroy test_bug1835705_vm$h
				sleep 5
				virsh undefine test_bug1835705_vm$h
			done
			rm -rf /home/sriov_test_delete_vm_with_kernel_args/images/*

			# clear cpu isolationg and nosmt parameter after finish test
			grubby --remove-args="nosmt=force" --update-kernel=$(grubby --default-kernel)
			tuned-adm off
			echo "2" > /tmp/reboot_num
			reboot
			sleep 300
		elif [ -f /tmp/reboot_num ] && [[ $(cat /tmp/reboot_num) == "2" ]]; then
			sync_set server test_delete_vm_with_kernel_args_end 14400
		fi
		rlRun "rm -rf /tmp/reboot_num"
	fi
}

sriov_test_reproduce_2000180()
{
	# https://bugzilla.redhat.com/show_bug.cgi?id=2000180
	# this case only reproduce bug 2000180, keep cpu0 as housekeeping any other cpu will be isolated.
	# test on rt-kernel will get panic about kernel BUG at drivers/pci/msi.c:375! on i40e driver.
	# test on stock kernel will get call trace as "NETDEV WATCHDOG: ens1f0v2 (iavf): transmit queue 1 timed out" on i40e
	# if the first time to create vf, panic will occurred on the first loop. But in this case, The VF will not be
	# created for the first time after the system is available， so panic will be trigger when run 23 times.
	rlLog "Setup sriov_test_reproduce_2000180"
	# /usr/sbin/kernel-is-rt || { echo "test kernel doesn't belong to realtime kernel, skip this case"; return 0; }
	if [ "$SYS_ARCH" == "ppc64le" ];then
		rlLogWarning "this case doesn't support to run on ppc64le, due to bug 2082433"
		return 0
	fi
	if i_am_server; then
		sync_set client sriov_test_reproduce_2000180_start ${SYNC_TIME}
		[ $? -eq 0 ] && sync_wait client sriov_test_reproduce_2000180_end ${SYNC_TIME}
		return 0
	fi

	/usr/bin/python3 -V &>/dev/null || yum -y install python3
	[[ -f /usr/bin/python ]] || ln -s $(which python3) /usr/bin/python

	local isolate_cores=$(get_cpu.py --bug_reproduce_2000180)
	rlLog "isolate core are ${isolate_cores}"
	if [ ! -f /tmp/sriov_test_reproduce_2000180_phase1 ]; then
		if ! uname -r | grep rt; then
			rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
			tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
		elif uname -r | grep rt; then
			rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
			echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
			tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
			systemctl disable irqbalance
			systemctl stop irqbalance
			rlLog "finish cpu tuning"
		fi
		rlLog "client finish hugepage configuration"
		echo "1" > /tmp/sriov_test_reproduce_2000180_phase1
		reboot
		sleep 300
	else
		rlRun "lscpu"
		rlRun "cat /proc/cmdline"
	fi
	if [ ! -f /tmp/sriov_test_reproduce_2000180_phase2 ]; then
		sync_wait server sriov_test_reproduce_2000180_start ${SYNC_TIME}
		echo 1 > /tmp/sriov_test_reproduce_2000180_phase2 2>/dev/null
		rlLog "Start test"
		local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
		rlLog "Test nic driver is ${DRIVER}"

		rlLog "Create 5 vfs and Check vf drive type"
		local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
		local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)

		if [[ ${MAX_VFS} -le 10 ]]; then
			local test_vfs=${MAX_VFS}
		else
			local test_vfs=6
		fi
		rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"
		rlRun "sriov_remove_vfs ${nic_test} 0"
		rlLog "try to create ${test_vfs} vfs"
		rlRun "sriov_create_vfs ${nic_test} 0 6"
		sleep 10

		local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
		local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
		local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
		if [ -z ${vf_driver_name} ]; then
			rlFail "can't find vf driver"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sync_set server sriov_test_reproduce_2000180_end ${SYNC_TIME}
			exit 1
		fi
		rlLog "check all vfs are created"
		if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
			rlFail "create the test vf of pf failed"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sync_set server sriov_test_reproduce_2000180_end ${SYNC_TIME}
			exit 1
		fi

		rlLog "check no mac adress is 00:00:00:00:00:00"
		for((i=0;i<$(expr $test_vfs); i++)); do
			local test_vf_mac=$(ip link show ${nic_test} | grep "vf $i" | awk '{print$4}')
			rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_vf_mac} "00:00:00:00:00:00"
		done

		rlLog "got all of vf name on a list"
		local vf_name_list

		for ((i=1;i<=${test_vfs};i++));do
			local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
			local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
			local vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			local vf_pci_list[$(expr $i - 1)]=${VF_PCI}
		done
		rlLog "vf_name_list equal is ${vf_name_list[*]}"
		rlLog "vf pci list equal is ${vf_pci_list[*]}"
		local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))
		rlLog "sort_vf_name_list equal is ${sort_vf_name_list[*]}"

		local vf_mac_list
		for ((i=1;i<=${test_vfs};i++));do
			vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
		done
		local vf_mac_list_length=${#vf_mac_list[@]}

		rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
		rlLog "got vf mac list: ${vf_mac_list[*]}"
		rlLog "got vf mac length: ${vf_mac_list_length}"
		rlLog "clean all vf and start test"
		rlRun "sriov_remove_vfs ${nic_test} 0"
		sleep 10
		rlLog "Beginning test"
		local MTU=9000
#		modprobe vfio_pci
		for ((xx=0; xx<=3; xx++));do
			echo $xx > /tmp/sriov_test_reproduce_2000180_xx

			for ((yy=0; yy<=10; yy++)); do
				echo $yy > /tmp/sriov_test_reproduce_2000180_yy
				# 1. set numvfs
				echo "1. set numvfs"
				echo "set ${test_vfs} vfs on ${nic_test}"
				sriov_remove_vfs ${nic_test} 0
				sriov_create_vfs ${nic_test} 0 ${test_vfs}
				# echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
				# echo ${test_vfs} > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
				sleep 5

				#2. set vf admin MAC address
				echo "2. set vf admin MAC address"
				for ((i=0; i<${vf_mac_list_length}; i++)); do
					ip link set dev ${nic_test} vf ${i} mac ${vf_mac_list[$i]}
				done

				# 3. unbind/bind vf driver
				echo "unbind/bind vf driver"
				for i in "${vf_pci_list[@]}"; do
					echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind 2>/dev/null
					echo > /sys/bus/pci/devices/${vf_pci}/driver_override 2>/dev/null
					echo ${i} > /sys/bus/pci/drivers_probe 2>/dev/null
				done

				# 4. set pf mtu
				echo "4. set pf mtu to ${MTU}"
				echo $MTU > /sys/class/net/${nic_test}/mtu

				#5. bind vf driver (if not already)
				#6. unbind/bind vf driver (workaround for bz1875338)
				echo "6. unbind/bind vf driver (workaround for bz1875338)"
				for i in "${vf_pci_list[@]}"; do
					echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind 2>/dev/null
					echo > /sys/bus/pci/devices/${vf_pci}/driver_override 2>/dev/null
					echo ${i} > /sys/bus/pci/drivers_probe 2>/dev/null
				done

				sleep 2
				#7. set vf mtu
				echo "7. set vf mtu to ${MTU}"
				for i in "${sort_vf_name_list[@]}"; do
					echo $MTU > /sys/class/net/${i}/mtu 2>/dev/null
				done

				#8. set pf up if not already
				echo "8. set pf up if not already"

				ip link set ${nic_test} up
				echo "Iteration: xx $xx, yy $yy"
				sleep 10
				# echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
				sriov_remove_vfs ${nic_test} 0
				echo "clean vf and reset mtu to 1500"
				ip link set mtu 1500 dev $nic_test
			done
		done
	fi

	rlLog "Check that the test ends in a normal loop"
	if [[ $(cat /tmp/sriov_test_reproduce_2000180_xx) -ne 3 ]] || [[ $(cat /tmp/sriov_test_reproduce_2000180_yy) -ne 10 ]]; then
		rlFail "The test did not end in a normal cycle. please check it!!!"
	fi

	# recover tunning configuration
	local isolate_cores=$(get_cpu.py --get_isolate_cpus_str)
	rlLog "isolate core are ${isolate_cores}"
	if [ ! -f /tmp/sriov_test_reproduce_2000180_phase3 ]; then
		if ! uname -r | grep rt; then
			rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
			tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
		elif uname -r | grep rt; then
			rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
			echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
			tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
			systemctl disable irqbalance
			systemctl stop irqbalance
		fi
		rlLog "finish cpu tuning"
		echo "1" > /tmp/sriov_test_reproduce_2000180_phase3
		reboot
		sleep 300
	fi
	sync_set server sriov_test_reproduce_2000180_end ${SYNC_TIME}
	rlLog "finish test and clean tag file"
	rm -rf /tmp/sriov_test_reproduce_2000180_xx
	rm -rf /tmp/sriov_test_reproduce_2000180_yy
	rm -rf /tmp/sriov_test_reproduce_2000180_phase3
	rm -rf /tmp/sriov_test_reproduce_2000180_phase2
	rm -rf /tmp/sriov_test_reproduce_2000180_phase1
	rlLog "check journald boot list"
	rlRun "journalctl --list-boots"
	local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
	rlLog "got prelate record id: ${prevlast}"
	rlLog "got last record id:${last}"
	rlRun "journalctl -o short-precise -k -b ${prevlast} | cat - | grep -C 50 -i 'call trace'" 1
	rlRun "journalctl -o short-precise -k -b | cat - | grep -C 50 -i 'call trace'" 1
	rlLog "finish test and clean tag file"
}


sriov_test_negative_create_vfs_2000180()
{
	# VFs are fully available when the echo command finishes.
	# BUT this means that PCI devices that represents VFs are available.
	# There is a second stage "binding the PCI device to driver" that is executed async.
	# it will got panic about "general protection fault: 0000 [#1] PREEMPT_RT SMP NOPTI"

	rlLog "Setup sriov_test_reproduce_negative_create_vfs_2000180"
	if i_am_server; then
		sync_set client sriov_test_negative_create_vfs_2000180_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		/usr/bin/python3 -V &>/dev/null || yum -y install python3
		[[ -f /usr/bin/python ]] || ln -s $(which python3) /usr/bin/python
		if [ "$SYS_ARCH" == "ppc64le" ];then
			local numa=$(get_info.sh nic_numa_node $nic_test)
			local isolate_cores=$(get_info.sh isolated_cores $numa)
		else
			local isolate_cores=$(get_cpu.py --get_isolate_cpus_str)
		fi
		rlLog "isolate core are ${isolate_cores}"
		if [ ! -f /tmp/sriov_test_negative_create_vfs_2000180_phase1 ]; then
			if ! uname -r | grep rt; then
				rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
				tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
			elif uname -r | grep rt; then
				rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
				echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
				tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
				systemctl disable irqbalance
				systemctl stop irqbalance
				rlLog "finish cpu tuning"
			fi
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=12" /proc/cmdline &>/dev/null)
			then
				setup_bootopts.sh \
				--hugepagesz=2G \
				--hugepages=12 \
				--isolated_cores="$isolate_cores" \
				--extra="intel_idle.max_cstate=0 processor.max_cstate=0 intel_pstate=disable" \
				--tuned-profiles=cpu-partitioning
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			# ! grep "rcupdate.rcu_normal_after_boot=0" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
			else
				rlLog "client finish hugepage configuration"
			fi
			echo "1" > /tmp/sriov_test_negative_create_vfs_2000180_phase1
			reboot
			sleep 300
		else
			rlLog "client finish cpu and hugepage tunning"
			rlRun "lscpu"
			rlRun "cat /proc/cmdline"
		fi

		if [ ! -f /tmp/sriov_test_negative_create_vfs_2000180_phase2 ]; then
			sync_wait server sriov_test_negative_create_vfs_2000180_start ${SYNC_TIME}
			rlLog "Start test"

			echo 1 > /tmp/sriov_test_negative_create_vfs_2000180_phase2 2>/dev/null
			local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
			rlLog "Test nic driver is ${DRIVER}"

			local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
			local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)
			local test_vfs=${MAX_VFS}
			rlLog "Create ${test_vfs} vfs and Check vf drive type"
			rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"

			rlRun "sriov_remove_vfs ${nic_test} 0"
			rlLog "try to create ${test_vfs} vfs"
			rlRun "sriov_create_vfs ${nic_test} 0 ${test_vfs}"
			sleep 120

			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
			if [ -z ${vf_driver_name} ]; then
				rlFail "can't find vf driver"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check all vfs are created"
			if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
				rlFail "create the test vf of pf failed"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check no mac adress is 00:00:00:00:00:00"
			for((i=1;i<=$(expr $test_vfs); i++)); do
				sriov_vfmac_is_zero ${nic_test} 0 ${i}
				local test_result=$?
				rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_result} 0
			done

			rlLog "got all of vf name on a list"
			local vf_name_list

			for ((i=1;i<=${test_vfs};i++));do
				local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
				local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
				vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			done

			local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))

			local vf_mac_list
			for ((i=1;i<=${test_vfs};i++));do
				vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
			done
			local vf_mac_list_length=${#vf_mac_list[@]}
			rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
			rlLog "got vf mac list: ${vf_mac_list[*]}"
			rlLog "got vf mac length: ${vf_mac_list_length}"
			rlLog "clean all vf and start test"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sleep 120
			rlLog "Beginning test"
			local MTU=9000

			for ((xx=0; xx<=3; xx++));do
				echo $xx > /tmp/sriov_test_negative_create_vfs_2000180_xx
				#not unload the VF driver in case the PF driver is the same one.
				#rmmod ${vf_driver_name}
				for ((yy=0; yy<=10; yy++)); do
					echo $yy > /tmp/sriov_test_negative_create_vfs_2000180_yy
					# 1. set numvfs
					echo "1. set numvfs"
					echo "set ${test_vfs} vfs on ${nic_test}"
					sriov_remove_vfs ${nic_test} 0
					sriov_create_vfs ${nic_test} 0 ${test_vfs}
					#2. set vf admin MAC address
					echo "2. set vf admin MAC address"
					for ((i=0; i<${vf_mac_list_length}; i++)); do
						ip link set dev ${sort_vf_name_list[$i]} address ${vf_mac_list[$i]}
					done

					# 3. unbind/bind vf driver
					echo "unbind/bind vf driver"
					for i in "${vf_pci_list[@]}"; do
						echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override
						echo ${i} > /sys/bus/pci/drivers_probe
					done

					# 4. set pf mtu
					echo "4. set pf mtu to ${MTU}"
					echo $MTU > /sys/class/net/${nic_test}/mtu

					#5. bind vf driver (if not already)
					#6. unbind/bind vf driver (workaround for bz1875338)
					echo "6. unbind/bind vf driver (workaround for bz1875338)"
					for i in "${vf_pci_list[@]}"; do
						echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override
						echo ${i} > /sys/bus/pci/drivers_probe
					done

					#7. set vf mtu
					echo "7. set vf mtu to ${MTU}"
					for i in "${sort_vf_name_list[@]}"; do
						echo $MTU > /sys/class/net/${i}/mtu
					done

					#8. set pf up if not already
					echo "8. set pf up if not already"

					ip link set ${nic_test} up
					echo "Iteration: xx $xx, yy $yy"
					sriov_remove_vfs ${nic_test} 0

					echo "clean vf and reset mtu to 1500"
					ip link set mtu 1500 dev $nic_test

				done
			done
		fi

		rlLog "Check that the test ends in a normal loop"
		if [[ $(cat /tmp/sriov_test_negative_create_vfs_2000180_xx) -ne 3 ]] || [[ $(cat /tmp/sriov_test_negative_create_vfs_2000180_yy) -ne 10 ]]; then
			rlFail "The test did not end in a normal cycle. please check it!!!"
		fi
		rlLog "finish test and clean tag file"
		sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_xx
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_yy
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_phase2
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_phase1
		rlLog "check journald boot list"
		rlRun "journalctl --list-boots"
		local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
		rlLog "got prelate record id: ${prevlast}"
		rlRun "journalctl -o short-precise -k -b ${prevlast} | cat - | grep -C 50 -i 'call trace'" 1
		rlRun "journalctl -o short-precise -k -b | cat - | grep -C 50 -i 'call trace'" 1
#		local user=$(cat /etc/motd | grep SUBMITTER | awk -F "=" '{print $2}' | sed  's/\(.*\)@.*/\1/g')
#		local jobid=$(cat /etc/motd | grep JOBID | awk -F "=" '{print $2}' | tr -d '\n' | tr -d " ")
#		local kernel_version=$(uname -r)
#		local hostname=$(hostname)
#		local file_list=$(find /var/crash/${user}/${KERNEL_VERSION}/${jobid}/${hostname}/ -name vmcore*)
#		if [[ ${file_list} != "" ]]; then
#			rlFail "can find vmcore file, need to check"
#		else
#			rlLog "can't find vmcore"
#		fi
		return 0

	fi
}

sriov_test_reproduce_2021326()
{
	# should got call trace as Oops: 0000 [#1] SMP NOPTI, only support ice & i40e
	# reproduce bug 2021326,2009461,1997012

	rlLog "Setup sriov_test_reproduce_2021326"
	if i_am_server; then
		sync_set client sriov_test_reproduce_2021326_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client sriov_test_reproduce_2021326_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		if [ ! -f /tmp/sriov_test_reproduce_2021326_phase1 ]; then
			local isolate_cores=$(get_cpu.py --get_isolate_cpus_str)
			rlLog "isolate core are ${isolate_cores}"
			if ! uname -r | grep rt; then
				rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
				tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
			elif uname -r | grep rt; then
				rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
				echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
				tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
				systemctl disable irqbalance
				systemctl stop irqbalance
				rlLog "finish cpu tuning"
			fi
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=12" /proc/cmdline &>/dev/null)
			then
				setup_bootopts.sh \
				--hugepagesz=2G \
				--hugepages=12 \
				--isolated_cores="$isolate_cores" \
				--extra="intel_idle.max_cstate=0 processor.max_cstate=0 intel_pstate=disable" \
				--tuned-profiles=cpu-partitioning
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			# ! grep "rcupdate.rcu_normal_after_boot=0" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
			else
				rlLog "client finish hugepage configuration"
			fi
			echo "1" > /tmp/sriov_test_reproduce_2021326_phase1
			reboot
			sleep 300
		else
			rlLog "client finish cpu and hugepage tunning"
			rlRun "lscpu"
			rlRun "cat /proc/cmdline"
		fi
		if [ ! -f /tmp/sriov_test_reproduce_2021326 ]; then
			sync_wait server sriov_test_reproduce_2021326_start ${SYNC_TIME}
			rlLog "Start test"
			echo 1 > /tmp/sriov_test_reproduce_2021326 2>/dev/null
			local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
			rlLog "Test nic driver is ${DRIVER}"

			rlLog "Create 10 vfs and Check vf drive type"
			local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
			local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)
			if [[ ${MAX_VFS} -le 10 ]]; then
				local test_vfs=${MAX_VFS}
			else
				local test_vfs=10
			fi
			rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"

			rlRun "sriov_remove_vfs ${nic_test} 0"
			rlLog "try to create ${test_vfs} vfs"
			rlRun "sriov_create_vfs ${nic_test} 0 ${test_vfs}"
			sleep 10

			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
			if [ -z ${vf_driver_name} ]; then
				rlFail "can't find vf driver"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check all vfs are created"
			if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
				rlFail "create the test vf of pf failed"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check no mac adress is 00:00:00:00:00:00"
			for((i=0;i<$(expr $test_vfs); i++)); do
				local test_vf_mac=$(ip link show ${nic_test} | grep "vf $i" | awk '{print$4}')
				rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_vf_mac} "00:00:00:00:00:00"
			done

			rlLog "got all of vf name on a list"
			local vf_name_list

			for ((i=1;i<=${test_vfs};i++));do
				local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
				local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
				vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			done

			local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))

			local vf_mac_list
			for ((i=1;i<=${test_vfs};i++));do
				vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
			done

			local vf_mac_list_length=${#vf_mac_list[@]}
			rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
			rlLog "got vf mac list: ${vf_mac_list[*]}"
			rlLog "got vf mac length: ${vf_mac_list_length}"
			rlLog "clean all vf and start test"
			rlRun "sriov_remove_vfs ${nic_test} 0"

			rlLog "Beginning test"
			local MTU=9000

			for ((xx=0; xx<=3; xx++));do
				echo $xx > /tmp/sriov_test_reproduce_2021326_xx
				rmmod ${vf_driver_name}
				sleep 1e-06
				for ((yy=0; yy<=10; yy++)); do
					echo $yy > /tmp/sriov_test_reproduce_2021326_yy
					# 1. set numvfs
					echo "1. set numvfs"
					echo "set ${test_vfs} vfs on ${nic_test}"
					echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs 2>/dev/null
					echo ${test_vfs} > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs 2>/dev/null
					sleep 1e-06
					#2. set vf admin MAC address
					echo "2. set vf admin MAC address"
					for ((i=1;i<=${test_vfs};i++)); do
						local vf_mac=${vf_mac_list[$(expr $i - 1)]}
						sleep 1e-06
						ip link set dev $nic_test vf $(expr $i - 1) mac ${vf_mac}
					done

					# 3. unbind/bind vf driver
					echo "unbind/bind vf driver"
					for ((i=1;i<=${test_vfs};i++)); do
						local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
						echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind 2>/dev/null
						sleep 1
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override 2>/dev/null
						sleep 1
						echo ${vf_pci} > /sys/bus/pci/drivers_probe 2>/dev/null
					done

					# 4. set pf mtu
					echo "4. set pf mtu to ${MTU}"
					echo $MTU > /sys/class/net/${nic_test}/mtu

					#5. bind vf driver (if not already)
					#6. unbind/bind vf driver (workaround for bz1875338)
					echo "6. unbind/bind vf driver (workaround for bz1875338)"
					for ((i=1;i<=${test_vfs};i++)); do
						local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
						echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind 2>/dev/null
						sleep 1e-06
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override 2>/dev/null
						sleep 1e-06
						echo ${vf_pci} > /sys/bus/pci/drivers_probe 2>/dev/null
					done
					sleep 1e-06

					#7. set vf mtu
					echo "7. set vf mtu to ${MTU}"
					for ((i=1;i<=${test_vfs};i++)); do
						vf_name=${sort_vf_name_list[$(expr $i - 1)]}
						echo $MTU > /sys/class/net/${vf_name}/mtu 2>/dev/null
					done

					#8. set pf up if not already
					echo "8. set pf up if not already"

					ip link set ${nic_test} up
					echo "Iteration: xx $xx, yy $yy"
					echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs 2>/dev/null
					sleep 1e-06
					echo "clean vf and reset mtu to 1500"
					ip link set mtu 1500 dev $nic_test

				done
			done
		fi
		rlLog "Check that the test ends in a normal loop"
		if [[ $(cat /tmp/sriov_test_reproduce_2021326_xx) -ne 3 ]] || [[ $(cat /tmp/sriov_test_reproduce_2021326_yy) -ne 10 ]]; then
			rlFail "The test did not end in a normal cycle. please check it!!!"
		fi

		sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
		rm -rf /tmp/sriov_test_reproduce_2021326
		rm -rf /tmp/sriov_test_reproduce_2021326_phase1
		rm -rf /tmp/sriov_test_reproduce_2021326_xx
		rm -rf /tmp/sriov_test_reproduce_2021326_yy
		rlLog "finish test and clean tag file"
		rlLog "check journald boot list"
		rlRun "journalctl --list-boots"
		local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
		rlLog "got prelate record id: ${prevlast}"
		rlRun "journalctl -o short-precise -k -b ${prevlast} | cat - | grep -C 50 -i 'call trace'" 1
		rlRun "journalctl -o short-precise -k -b | cat - | grep -C 50 -i 'call trace'" 1
		rlLog "finish test and clean tag file"
#		local user=$(cat /etc/motd | grep SUBMITTER | awk -F "=" '{print $2}' | sed  's/\(.*\)@.*/\1/g')
#		local jobid=$(cat /etc/motd | grep JOBID | awk -F "=" '{print $2}' | tr -d '\n' | tr -d " ")
#		local kernel_version=$(uname -r)
#		local hostname=$(hostname)
#		local file_list=$(find /var/crash/${user}/${KERNEL_VERSION}/${jobid}/${hostname}/ -name vmcore*)
#		if [[ ${file_list} != "" ]]; then
#			rlFail "can find vmcore file, need to check"
#		else
#			rlLog "can't find vmcore"
#		fi
		return 0

	fi
}


sriov_test_reproduce_2021326_reboot_check()
{
	rlLog "Setup sriov_test_reproduce_2021326_reboot_check"
	if i_am_server; then
		sync_set client sriov_test_reproduce_2021326_reboot_check_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client sriov_test_reproduce_2021326_reboot_check_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		if [ ! -f /tmp/sriov_test_reproduce_2021326_reboot_check ]; then
			sync_wait server sriov_test_reproduce_2021326_reboot_check_start ${SYNC_TIME}
			rlLog "Start test"
			local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
			rlLog "Test nic driver is ${DRIVER}"

			rlLog "Create 10 vfs and Check vf drive type"
			local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
			local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)
			if [[ ${MAX_VFS} -le 10 ]]; then
				local test_vfs=${MAX_VFS}
			else
				local test_vfs=10
			fi
			rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"

			rlRun "sriov_remove_vfs ${nic_test} 0"
			rlLog "try to create ${test_vfs} vfs"
			rlRun "sriov_create_vfs ${nic_test} 0 ${test_vfs}"
			sleep 10

			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
			if [ -z ${vf_driver_name} ]; then
				rlFail "can't find vf driver"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_reboot_check_end
				exit 1
			fi

			rlLog "check all vfs are created"
			if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
				rlFail "create the test vf of pf failed"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_reboot_check_end
				exit 1
			fi

			rlLog "check no mac adress is 00:00:00:00:00:00"
			for((i=0;i<$(expr $test_vfs); i++)); do
				local test_vf_mac=$(ip link show ${nic_test} | grep "vf $i" | awk '{print$4}')
				rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_vf_mac} "00:00:00:00:00:00"
			done

			rlLog "got all of vf name on a list"
			local vf_name_list
			for ((i=1;i<=${test_vfs};i++));do
				local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
				local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
				vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			done

			local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))

			local vf_mac_list
			for ((i=1;i<=${test_vfs};i++));do
				vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
			done
			local vf_mac_list_length=${#vf_mac_list[@]}
			rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
			rlLog "got vf mac list: ${vf_mac_list[*]}"
			rlLog "got vf mac length: ${vf_mac_list_length}"
			rlLog "clean all vf and start test"
			rlRun "echo 0 > /sys/class/net/${nic_test}/device/sriov_numvfs 2>/dev/null"

			rlLog "Beginning test"
			set -x
			local MTU=9000
			modprobe -r vfio-pci
			sleep 1
			modprobe -r vfio
			sleep 1
			modprobe vfio-pci
			sleep 1
			modprobe vfio
			sleep 1
			rmmod ${vf_driver_name}
			sleep 1

			# 1. set numvfs
			echo "1. set numvfs"
			echo "set ${test_vfs} vfs on ${nic_test}"
			echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs 2>/dev/null
			echo ${test_vfs} > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs 2>/dev/null
			sleep 5


			#2. set vf admin MAC address
			echo "2. set vf admin MAC address"
			for ((i=1;i<=${test_vfs};i++)); do
				local vf_mac=${vf_mac_list[$(expr $i - 1)]}
				ip link set dev $nic_test vf $(expr $i - 1) mac ${vf_mac}
			done


			# 3. unbind/bind vf driver
			echo "unbind/bind vf driver"
			for ((i=1;i<=${test_vfs};i++)); do
				local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
				echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind 2>/dev/null
				echo > /sys/bus/pci/devices/${vf_pci}/driver_override 2>/dev/null
				echo ${vf_pci} > /sys/bus/pci/drivers_probe 2>/dev/null
			done

			# 4. set pf mtu
			echo "4. set pf mtu to ${MTU}"
			echo $MTU > /sys/class/net/${nic_test}/mtu

			#5. bind vf driver (if not already)
			#6. unbind/bind vf driver (workaround for bz1875338)
			echo "6. unbind/bind vf driver (workaround for bz1875338)"
			for ((i=1;i<=${test_vfs};i++)); do
				local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
				echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind 2>/dev/null
				echo > /sys/bus/pci/devices/${vf_pci}/driver_override 2>/dev/null
				echo ${vf_pci} > /sys/bus/pci/drivers_probe 2>/dev/null
			done

			sleep 2

			#7. set vf mtu
			echo "7. set vf mtu to ${MTU}"
			for ((i=1;i<=${test_vfs};i++)); do
				vf_name=${sort_vf_name_list[$(expr $i - 1)]}
				echo $MTU > /sys/class/net/${vf_name}/mtu 2>/dev/null
			done


			#8. set pf up if not already
			echo "8. set pf up if not already"
			ip link set ${nic_test} up
			sleep 5
			echo "clean vf and reset mtu to 1500"
			echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs 2>/dev/null
			sleep 5
			ip link set mtu 1500 dev $nic_test
			echo 1 > /tmp/sriov_test_reproduce_2021326_reboot_check 2>/dev/null
			reboot
			sleep 300
		else
			rlLog "check journald boot list"
			rlRun "journalctl --list-boots"
			local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
			rlLog "got prelate record id: ${prevlast}"
			rlRun "journalctl -o short-precise -k -b ${prevlast} | cat - | grep -C 50 -i 'call trace'" 1
			rlRun "journalctl -o short-precise -k -b | cat - | grep -C 50 -i 'call trace'" 1
			rlLog "finish test and clean tag file"
			rm -rf /tmp/sriov_test_reproduce_2021326_reboot_check
			sync_set server sriov_test_reproduce_2021326_reboot_check_end ${SYNC_TIME}
		fi
		return 0

	fi
}

sriov_test_2175775_reboot_with_vfs()
{
	if i_am_server; then
		sync_set client sriov_test_2175775_reboot_with_vfs_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client sriov_test_2175775_reboot_with_vfs_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		rlLog "current RECIPEID is: ${RECIPEID}"
		rlLog "current TASKID is: ${TASKID}"

		if [ ! -f /tmp/sriov_test_2175775_reboot_with_vfs ]; then
			sync_wait server sriov_test_2175775_reboot_with_vfs_start ${SYNC_TIME}
			rlLog "Start test"

			rlLog "Create 10 vfs and Check vf drive type"
			local MAX_VFS=$(sriov_get_max_vf_from_pf $nic_test 0)
			if [[ ${MAX_VFS} -le 10 ]]; then
				local test_vfs=${MAX_VFS}
			else
				local test_vfs=10
			fi
			rlRun "sriov_remove_vfs ${nic_test} 0"
			rlLog "try to create ${test_vfs} vfs"
			rlRun "sriov_create_vfs ${nic_test} 0 ${test_vfs}"
			sleep 10
			echo 1 > /tmp/sriov_test_2175775_reboot_with_vfs 2>/dev/null
			rstrnt-reboot
		else
			rlLog "check journald boot list"
			rlRun "journalctl --list-boots"
			local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
			rlLog "got prelate record id: ${prevlast}"
			rlRun "journalctl -o short-precise -k -b ${prevlast} | cat - | grep -C 50 -i 'call trace'" 1
			rlRun "journalctl -o short-precise -k -b | cat - | grep -C 50 -i 'call trace'" 1
			rlLog "finish test and clean tag file"
			rm -rf /tmp/sriov_test_2175775_reboot_with_vfs
			sync_set server sriov_test_2175775_reboot_with_vfs_end ${SYNC_TIME}
		fi
		return 0

	fi
}
sriov_test_vf_cfg_stress()
{
	#reproducer for bz1997012 bz1996954, cfg vf in loop, should just fail without a kernel panic
	ip link set $nic_test up
	if i_am_server; then
		sync_set client test_vf_cfg_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_vf_cfg_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
		sync_set client test_bz2027588_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_bz2027588_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		ip link set $nic_test up
		if [ -f /tmp/sriov_test_vf_cfg_stress ]; then
			rm -rf /tmp/sriov_test_vf_cfg_stress
		fi
		touch /tmp/sriov_test_vf_cfg_stress

		sync_wait server test_vf_cfg_start ${SYNC_TIME}
		rlLog "start sriov_test_vf_cfg_stress test"
		echo 1 > /tmp/sriov_test_vf_cfg_stress 2>/dev/null
		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_vf_cfg_end ${SYNC_TIME}
			return 1
		fi
		local VF=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$VF" ]; then
			rlFail "FAIL to get VF interface"
			result=1
			sync_set server test_vf_cfg_end ${SYNC_TIME}
		else
			ethtool -i $VF
			change_vf_cfg_in_loop()
			{
				# clear dmesg
				sriov_remove_vfs $nic_test 0
				for ((i=0; i<500; i++)); do
					echo "create vf"
					ip link set $nic_test up

					sriov_create_vfs $nic_test 0 1
					# change vf cfg
					for i in `seq 0 100`;do
						ip link set $nic_test vf 0 trust on spoofchk on
						sleep 1
						ip link set $nic_test vf 0 trust off spoofchk off
						sleep 1
						ip link set $nic_test vf 0 trust on spoofchk on
						sleep 1
					done
					echo "remove vf"
					sriov_remove_vfs $nic_test 0
				done
			}
			vf_in_netns()
			{
				# clear netns
				ip netns del ns1 &>/dev/null
				# create netns
				ip netns add ns1
				ip netns exec ns1 ip link add name br0 type bridge
				ip netns exec ns1 ip link set br0 up
				# vf option
				while :;do
					[ -z "$VF" ] && { continue; }
					echo "setup vf in netns"
					ip link set $VF address "22:00:01:02:03:04" && echo "set mac succeeded 1"
					ip link set $VF netns ns1
					ip netns exec ns1 ip link set $VF up
					ip netns exec ns1 ip link set $VF master br0
					ip netns exec ns1 ip link set $VF address "22:00:01:02:03:05" && echo "set mac succeeded 2"
					ip netns exec ns1 ip link set $VF netns 1
				done
				# remove netns
				ip netns del ns1
			}
			(
				local cnt=60
				change_vf_cfg_in_loop > /tmp/sriov_test_vf_cfg_stress 2>&1 &
				local child2=$!
				vf_in_netns > /tmp/sriov_test_vf_cfg_stress 2>&1 &
				local child1=$!
				trap -- "" SIGTERM
				(
					while [ $cnt -gt 0 ] ; do
						if grep -i "Device or resource busy" /tmp/sriov_test_vf_cfg_stress ; then
							rlFail "SR-IOV stress test failed!"
							break
						fi
						sleep 60
						(( cnt -- ))
					done
					kill $child1 2> /dev/null
					kill $child2 2> /dev/null
				) &
				wait $child1
				wait $child2
			)
			sync_set server test_vf_cfg_end ${SYNC_TIME}
			sriov_remove_vfs $nic_test 0
			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_bz2027588_end ${SYNC_TIME}
				return 1
			fi
			sync_wait server test_bz2027588_start ${SYNC_TIME}
			attach_and_detach_vf_in_loop()
			{
				while :;do
					# create vf
					ip link set $nic_test up
					sriov_remove_vfs $nic_test 0
					sriov_create_vfs $nic_test 0 1
					# attch and detach
					for i in `seq 10`;do
						sriov_attach_vf_to_vm $nic_test 0 1 g1 22:22:22:22:22:$(printf %02x $MAC)
						sleep 2
						sriov_detach_vf_from_vm $nic_test 0 1 g1
						sleep 2
						dmesg | grep -i busy && break
					done
					wait
					# remove vf
					sriov_remove_vfs $nic_test 0
				done
			}
			(
				attach_and_detach_vf_in_loop &
				local child3=$!
				change_vf_cfg_in_loop &
				local child4=$!
				trap -- "" SIGTERM
				(
					sleep 3600
					kill $child3 2> /dev/null
					kill $child4 2> /dev/null
				) &
				wait $child3
				wait $child4
			)
		fi
		sync_set server test_bz2027588_end ${SYNC_TIME}
		sriov_remove_vfs $nic_test 0
	fi
}

sriov_test_2049237_VF_mac_reset_zero()
{
	if i_am_server ; then
		sync_set client test_VF_mac_reset_zero_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_VF_mac_reset_zero_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else

		if [ ! -f /tmp/sriov_test_2049237_VF_mac_reset_zero ]; then
			# configure hugepage before start test.
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=12" /proc/cmdline &>/dev/null)
			then
				rlLog "grubby --args=\"default_hugepagesz=2G hugepagesz=2G hugepages=12\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=2G hugepagesz=2G hugepages=12" --update-kernel=$(grubby --default-kernel)
				reboot
				sleep 300
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
				reboot
				sleep 300
			else
				rlLog "client finish hugepage configuration"
			fi

			sync_wait server test_VF_mac_reset_zero_start ${SYNC_TIME}

			echo 1 > /tmp/sriov_test_2049237_VF_mac_reset_zero 2>/dev/null
			rpm -q dpdk || yum install -y dpdk 2>/dev/null || rlFail "install dpdk failed"
			rpm -q dpdk-tools || yum install -y dpdk-tools 2>/dev/null || rlFail "install dpdk failed"

			modprobe -r vfio-pci
			sleep 1
			modprobe -r vfio
			sleep 1
			modprobe vfio-pci
			sleep 1
			modprobe vfio
			sleep 1

			ip link set $nic_test up
			sriov_create_vfs ${nic_test} 0 8 || { rlFail "Create vf failed on ${nic_test}"; sync_set server test_VF_mac_reset_zero_end; }
			ip link show ${nic_test}
			local dpdk_devbind_path=$(rpm -ql dpdk-tools | grep devbind.py$)
			local testpmd_cmd=$(rpm -ql dpdk | grep testpmd$)
			local vf1_name=$(sriov_get_vf_iface ${nic_test} 0 1)
			local vf2_name=$(sriov_get_vf_iface ${nic_test} 0 2)
			local vf1_pci=$(sriov_get_vf_bus_info ${nic_test} 0 1)
			local vf2_pci=$(sriov_get_vf_bus_info ${nic_test} 0 2)

			$dpdk_devbind_path --status
			ip link set ${vf1_name} down
			ip link set ${vf2_name} down
			local driver_name=$(ethtool -i ${nic_test}| grep driver | awk '{print $NF}')
			if [[ ${driver_name} =~ mlx.* ]]; then
				echo "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf1_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			# workaround https://bugzilla.redhat.com/show_bug.cgi?id=2128171
			rlLog "full of testpmd cmd is: \"${testpmd_cmd} -a ${vf1_pci} -a ${vf2_pci} -n 4 --iova-mode=va -- -i --nb-cores=1 --forward-mode=mac --port-topology=loop --no-mlockall\""
			nohup sh -c "(while sleep 1; do echo show port info all; done | ${testpmd_cmd} -a ${vf1_pci} -a ${vf2_pci} -n 4 --iova-mode=va -- -i --nb-cores=1 --forward-mode=mac --port-topology=loop --no-mlockall) &>/tmp/testpmd.log &"
			sleep 10
			sed -n '1,500p' /tmp/testpmd.log
			while [[ $(ps -aux | grep testpmd | grep -v "grep" | wc -l) -ne 0 ]]; do
				pkill -9 testpmd
				sleep 5
			done

			ip link show ${nic_test}

			local vf1_mac=$(ip link show ${nic_test} | grep "vf 0" | awk '{print$4}')
			local vf2_mac=$(ip link show ${nic_test} | grep "vf 1" | awk '{print$4}')
			rlAssertNotEquals "check ${vf1_name} mac equal 00:00:00:00:00:00" ${vf1_mac} "00:00:00:00:00:00"
			rlAssertNotEquals "check ${vf2_name} mac equal 00:00:00:00:00:00" ${vf2_mac} "00:00:00:00:00:00"

			if [[ ${driver_name} =~ mlx.* ]]; then
				echo "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf1_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			sriov_remove_vfs ${nic_test} 0
			rm -rf /tmp/sriov_test_2049237_VF_mac_reset_zero
			sync_set server test_VF_mac_reset_zero_end ${SYNC_TIME}
		else
			rm -rf /tmp/sriov_test_2049237_VF_mac_reset_zero
			sync_set server test_VF_mac_reset_zero_end ${SYNC_TIME}
		fi
	fi

}

sriov_test_2049237_VF_mac_reset_zero_reboot_check()
{
	if i_am_server ; then
		sync_set client test_VF_mac_reset_zero_reboot_check_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_VF_mac_reset_zero_reboot_check_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		# after do test, need reboot to check whether call trace occurred.
		if [ ! -f /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check ]; then
			# configure hugepage before start test.
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null)
			then
				rlLog "grubby --args=\"default_hugepagesz=2G hugepagesz=2G hugepages=24\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=2G hugepagesz=2G hugepages=24" --update-kernel=$(grubby --default-kernel)
				reboot
				sleep 300
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
				reboot
				sleep 300
			else
				rlLog "client finish hugepage configuration"
			fi
			rpm -q dpdk || yum install -y dpdk 2>/dev/null || rlFail "install dpdk failed"
			rpm -q dpdk-tools || yum install -y dpdk-tools 2>/dev/null || rlFail "install dpdk failed"

			rlRun "modprobe -r vfio-pci"
			sleep 1
			rlRun "modprobe -r vfio"
			sleep 1
			rlRun "modprobe vfio-pci"
			sleep 1
			rlRun "modprobe vfio"
			sleep 1
			rlRun "lsmod | grep vfio"
			rlRun "ip link set $nic_test up"
			sriov_create_vfs ${nic_test} 0 8 || { rlFail "Create vf failed on ${nic_test}";sync_wait server test_VF_mac_reset_zero_reboot_check_start; sync_set server test_VF_mac_reset_zero_reboot_check_end; }
			rlRun "ip link show ${nic_test}"
			local dpdk_devbind_path=$(rpm -ql dpdk-tools | grep devbind.py$)
			local testpmd_cmd=$(rpm -ql dpdk | grep testpmd$)
			local vf1_name=$(sriov_get_vf_iface ${nic_test} 0 1)
			local vf2_name=$(sriov_get_vf_iface ${nic_test} 0 2)
			local vf1_pci=$(sriov_get_vf_bus_info ${nic_test} 0 1)
			local vf2_pci=$(sriov_get_vf_bus_info ${nic_test} 0 2)

			rlRun "$dpdk_devbind_path --status"
			rlRun "ip link set ${vf1_name} down"
			rlRun "ip link set ${vf2_name} down"
			local driver_name=$(ethtool -i ${nic_test}| grep driver | awk '{print $NF}')
			if [[ ${driver_name} =~ mlx.* ]]; then
				rlLog "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf1_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			local dpdk_version=$(rpm -q --queryformat '%{VERSION}' dpdk-tools | awk -F '.' '{print $1}')
			if (( ${dpdk_version} > 20 )); then
				local allow_list_option='-a'
			else
				local allow_list_option='-w'
			fi
			nohup sh -c "(while sleep 1; do echo show port info all; done | ${testpmd_cmd} ${allow_list_option} ${vf1_pci} ${allow_list_option} ${vf2_pci} -n 4 --iova-mode=va -- -i --nb-cores=5 --forward-mode=mac --port-topology=loop --no-mlockall) &>/tmp/testpmd.log &"
			sleep 10
			sed -n '1,500p' /tmp/testpmd.log
			while [[ $(ps -aux | grep testpmd | grep -v "grep" | wc -l) -ne 0 ]]; do
				pkill -9 testpmd
				sleep 5
			done

			ip link show ${nic_test}

			local vf1_mac=$(ip link show ${nic_test} | grep "vf 0" | awk '{print$4}')
			local vf2_mac=$(ip link show ${nic_test} | grep "vf 1" | awk '{print$4}')
			rlAssertNotEquals "check ${vf1_name} mac equal 00:00:00:00:00:00" ${vf1_mac} "00:00:00:00:00:00"
			rlAssertNotEquals "check ${vf2_name} mac equal 00:00:00:00:00:00" ${vf2_mac} "00:00:00:00:00:00"

			if [[ ${driver_name} =~ mlx.* ]]; then
				rlLog "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf1_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			sync_wait server test_VF_mac_reset_zero_reboot_check_start ${SYNC_TIME}
			sriov_remove_vfs ${nic_test}
			echo "1" > /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check
			reboot
			sleep 300
		else
			rlLog "check journald boot list"
			rlRun "journalctl --list-boots"
			local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
			rlLog "got prelate record id: ${prevlast}"
			rlRun "journalctl -o short-precise -k -b ${prevlast} | cat - | grep -C 50 -i 'call trace'" 1
			rlRun "journalctl -o short-precise -k -b | cat - | grep -C 50 -i 'call trace'" 1
			rm -rf /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check
			sync_set server test_VF_mac_reset_zero_reboot_check_end ${SYNC_TIME}
		fi
	fi
}
sriov_test_2188249()
{
	if i_am_server ; then
		sync_set client test_VF_mac_reset_zero_reboot_check_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_VF_mac_reset_zero_reboot_check_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		# after do test, need reboot to check whether call trace occurred.
		if [ ! -f /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check ]; then
			# configure hugepage before start test.
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null)
			then
				rlLog "grubby --args=\"default_hugepagesz=2G hugepagesz=2G hugepages=24\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=2G hugepagesz=2G hugepages=24" --update-kernel=$(grubby --default-kernel)
				reboot
				sleep 300
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
				reboot
				sleep 300
			else
				rlLog "client finish hugepage configuration"
			fi

			rlRun "ip link set $nic_test up"
			sriov_create_vfs ${nic_test} 0 8 || { rlFail "Create vf failed on ${nic_test}";sync_wait server test_VF_mac_reset_zero_reboot_check_start; sync_set server test_VF_mac_reset_zero_reboot_check_end; }
			rlRun "ip link show ${nic_test}"
			sync_wait server test_VF_mac_reset_zero_reboot_check_start ${SYNC_TIME}
			sriov_remove_vfs ${nic_test}
			echo "1" > /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check
			reboot
			sleep 300
		else
			rlLog "check journald boot list"
			rlRun "journalctl --list-boots"
			local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
			rlLog "got prelate record id: ${prevlast}"
			rlRun "journalctl -o short-precise -k -b ${prevlast} | cat - | grep -C 50 -i 'call trace'" 1
			rlRun "journalctl -o short-precise -k -b | cat - | grep -C 50 -i 'call trace'" 1
#			rlLog "cleanup journald setting"
#			rlRun "systemd-tmpfiles --clean --prefix /var/log/journal/"
#			rlRun "systemd-tmpfiles --remove --prefix /var/log/journal/"
#			rlRun "systemctl restart systemd-journald.service"
			rm -rf /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check
			sync_set server test_VF_mac_reset_zero_reboot_check_end ${SYNC_TIME}
		fi
	fi
}

sriov_test_reproduce_2057244_and_2070917_ns(){
	# for 2057244 should got Invalid message from VF 0, opcode 3, len 4, error -1
	# for 2070917 should ping failed when first time. ip netns exec sriov_test_reproduce_2057244_ns ping -c3 172.3.${ipaddr}.188

	if i_am_server; then
		sync_set client sriov_test_reproduce_2057244_and_2070917_ns_start
		if [ $? -eq 0 ]; then
			local test_nic=$(get_test_nic)
			rlLog "test nic is: ${test_nic}"
			rlRun "ip link set ${test_nic} up"
			rlRun "ip link add link ${test_nic} name ${test_nic}.3 type vlan id 3" # can use random vlan
			rlRun "ip addr add 172.3.${ipaddr}.188/24 dev ${test_nic}.3" # can use random vlan
			rlRun "ip link set ${test_nic}.3 up" # can use random IP address
			nohup ping -I ${test_nic}.3 172.3.${ipaddr}.111 &
			sync_wait client sriov_test_reproduce_2057244_and_2070917_ns_end
			if [ $? -eq 0 ]; then
				rlLog "finish sriov_test_reproduce_2057244_ns"
			else
				rlFail "sync error need to check"
			fi
			pkill -9 ping
			ip addr flush ${test_nic}.3
			ip link del ${test_nic}.3
		else
			rlFail "sync error need to check"
			exit 1
		fi
	else
		sync_wait server sriov_test_reproduce_2057244_and_2070917_ns_start
		if [ $? -eq 0 ]; then
			local test_nic=$(get_test_nic)
			local random_mac=$(get_mac_prefix $(hostname))
			local vf_mac="${random_mac}02:02"
			rlLog "got vf randon mac is: ${vf_mac}"
			rlRun "ip link set ${test_nic} up"
			rlLog "test nic is: ${test_nic}"
			rlLog "try to got vf0 name"
			local PF_PCI=$(sriov_get_pf_bus_info ${test_nic} 0)
			rlRun "echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs 2>/dev/null"
			rlLog "try to create 1 vfs"
			rlRun "echo 1 > /sys/class/net/${test_nic}/device/sriov_numvfs 2>/dev/null"
			sleep 10
			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			rlLog "got vf 0 name is: ${check_vf_name}"
			rlRun "echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs 2>/dev/null"
			sleep 10
			for i in $(seq 1 100); do
				rlLog "start $i test"
				modprobe -r bridge
				echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs 2>/dev/null
				ip li > /dev/null
				echo 8 > /sys/class/net/${test_nic}/device/sriov_numvfs 2>/dev/null
				sleep 3
				ip link set ${test_nic} vf 0 vlan 3
				ip netns add sriov_test_reproduce_2057244_ns
				ip link set dev ${check_vf_name} netns sriov_test_reproduce_2057244_ns
				ip netns exec sriov_test_reproduce_2057244_ns ip link add dev br0 type bridge
				ip netns exec sriov_test_reproduce_2057244_ns ip link set ${check_vf_name} master br0
				ip netns exec sriov_test_reproduce_2057244_ns ip link set ${check_vf_name} up
				ip netns exec sriov_test_reproduce_2057244_ns ip link set br0 up
				ip netns exec sriov_test_reproduce_2057244_ns ip addr flush br0
				ip netns exec sriov_test_reproduce_2057244_ns ip addr add 172.3.${ipaddr}.111/24 dev br0 # can use random IP address
				ip netns exec sriov_test_reproduce_2057244_ns ping -c3 172.3.${ipaddr}.188 || {
					rlFail "Ping failed when run $i cycle"
				}
				ip link set ${test_nic} vf 0 mac ${vf_mac}
				ip netns exec sriov_test_reproduce_2057244_ns ip link set br0 address ${vf_mac}
				ip netns exec sriov_test_reproduce_2057244_ns ping -c3 172.3.${ipaddr}.188 || {
					rlFail "Ping failed when run $i cycle"
				}
				ip link set ${test_nic} vf 0 vlan 0
				ip link set ${test_nic} vf 0 trust on
				ip link set ${test_nic} vf 0 trust off
				ip link set ${test_nic} vf 0 trust on
				ip link set ${test_nic} vf 0 trust off
				ip link set ${test_nic} vf 0 trust on
				ip netns exec sriov_test_reproduce_2057244_ns ip addr flush br0
				ip netns exec sriov_test_reproduce_2057244_ns ip link add link br0 name br0.3 type vlan id 3
				ip netns exec sriov_test_reproduce_2057244_ns ip link set br0.3 up
				ip netns exec sriov_test_reproduce_2057244_ns ip addr add 172.3.${ipaddr}.111/24 dev br0.3 # can use random IP address
				ip netns exec sriov_test_reproduce_2057244_ns ping -c5 172.3.${ipaddr}.188 || {
					rlFail "Ping failed when run $i cycle"
					rlRun "ip netns exec sriov_test_reproduce_2057244_ns ip link show"
					rlRun "ip netns exec sriov_test_reproduce_2057244_ns ip link show | grep -w NO-CARRIER" "1-255"
					break
				}
				rlLog "finish $i test"
				ip netns del sriov_test_reproduce_2057244_ns
			done
			rlLog "clean test configuration"
			rlRun "ip netns del sriov_test_reproduce_2057244_ns" "0,1"
			rlRun "echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs 2>/dev/null"
			sync_set server sriov_test_reproduce_2057244_and_2070917_ns_end
		else
			rlFail "sync error with server"
			exit 1
		fi
	fi
}
sriov_test_bz2008373() {
		if i_am_server ; then
			sync_set client sriov_test_bz2008373_start  52200
			sync_wait client sriov_test_bz2008373_end 52200
		else
			sync_wait server sriov_test_bz2008373_start  52200
			rlLog "start to test sriov_test_bz2008373_start"
			local nic_name=$(get_test_nic 1)
			PCI=$(ethtool -i ${nic_name} | grep bus | cut -d " " -f 2)
			vf_max_num=$(cat /sys/class/net/${nic_name}/device/sriov_totalvfs)
			[ ${vf_max_num} -lt 64 ] && vf_num=${vf_max_num} || vf_num=64
			echo  ${vf_num} > /sys/bus/pci/devices/$PCI/sriov_numvfs 2>/dev/null
			loop_num=$(expr ${vf_num} - 1)
			for VF in $(seq 0 ${loop_num})
			do
				echo "loop time: $VF"
				vf="vf$VF"
				echo "vf name: $vf"
				for i in {1..10001}
				do
						{ ip link set ${nic_name} vf $VF trust on;ip link set ${nic_name} vf $VF vlan 10 qos 1;ip link set ${nic_name} vf $VF vlan 0 qos 0; }
						[ $? -ne 0 ] && echo "bug occur" && result=1 && break 2
				done
			done
			ip -d link show ${nic_name}
			echo 0 > /sys/bus/pci/devices/$PCI/sriov_numvfs 2>/dev/null

			sync_set server sriov_test_bz2008373_end  52200
		fi
		return $result
}
# vf_intf_garp_check is for bz1938635
vf_intf_garp_check() {
	rlLog "vf_intf_garp_check is for bz1938635"
	result=0
	if i_am_server; then
		sync_set client vf_intf_garp_check_start
		sync_wait client vf_intf_garp_check_end
	else
		rlLog "start to test client vf_intf_arp_check"
		sync_wait server vf_intf_garp_check_start
		local nic_test=$(get_test_nic 1)
		PF_PCI=$(ethtool -i ${nic_test} | grep bus | cut -d " " -f 2)
		#1.enable sriov
		rlLog "STEP 1: Enable sriov on client"
		sriov_create_vfs ${nic_test} 0 1
		sleep 3
		#2. set ip addr for vf
		rlLog "STEP 2: Set IP address for vf interface"
		local VF_IFACE=$(sriov_get_vf_iface $nic_test 0 1)
		ip addr add 172.30.${ipaddr}.2/24 dev ${VF_IFACE}
		ip link set $VF_IFACE up
		#3.set arp_notify for GARP
		rlLog "STEP 3: Set arp_notify for PF and vf"
		pf_garp_status=$(cat /proc/sys/net/ipv4/conf/${nic_test}/arp_notify)
		vf_garp_status=$(cat /proc/sys/net/ipv4/conf/${VF_IFACE}/arp_notify)
		[ ${pf_garp_status} -eq 0 ] && echo 1 > /proc/sys/net/ipv4/conf/${nic_test}/arp_notify
		[ ${vf_garp_status} -eq 0 ] && echo 1 > /proc/sys/net/ipv4/conf/${VF_IFACE}/arp_notify
		#4. set effective mac for vf and check the effective mac address whether be applied
		rlLog "STEP 4: set effective mac for vf , then check the effective mac address whether be applied, and if the garp packets are sent"
		vf_mac=00:11:22:33:44:10
		timeout 20  tcpdump -Q out  -nn -e  -i  ${VF_IFACE} arp  -w 1.pcap &
		sleep 8
		ip link set ${VF_IFACE} addr ${vf_mac}
		sleep 13
		ip link show ${VF_IFACE} | grep -i  ${vf_mac}
		[ $? -eq 0 ] ||  { result=1; rlFail "step 4: configure link mac ${vf_mac} failed"; ip link show ${VF_IFACE}; }
		#check the GARP packets
		tcpdump -r 1.pcap -enn | grep  -i  "${vf_mac} > ff:ff:ff:ff:ff:ff"
		[ $? -eq 0 ] || { result=1; tcpdump -r 1.pcap -enn; rlFail "step 4: No garp packets captured for mac ${vf_mac}"; }
		#5.  set the admin mac for vf and check the mac when nic_driver= ice or i40e
		if  [ "$NIC_DRIVER" = "ice" ] || [ "$NIC_DRIVER" = "i40e" ]; then

			rlLog "STEP 5: Set the admin mac for vf and check if the mac is set successfully"
			vf_mac1=00:11:22:33:44:11
			ip link set ${nic_test} vf 0 mac ${vf_mac1}
			sleep 3
			ip link show ${VF_IFACE} | grep -i  ${vf_mac1}
			[ $? -eq 0 ] ||  { result=1; rlFail "${vf_mac1} : configure link mac failed"; ip link show ${VF_IFACE}; }

			#6.set the effective mac for vf
			rlLog "STEP 6: Set mac for vf interface and check if the mac is set successfully"
			vf_mac2=00:11:22:33:44:12
			info=$(ip link set ${VF_IFACE} addr ${vf_mac2} 2>&1)
			[[ $info == "RTNETLINK answers: Permission denied" ]] || { result=1; rlFail "There should be error info"; rlLog "The current info is $info"; }
			sleep 3
			ip link show ${VF_IFACE} | grep -i  ${vf_mac2}
			[ $? -ne 0 ] ||  { result=1; rlFail "step6 : configure link mac ${vf_mac2} should  fail"; ip link show ${VF_IFACE}; }
		fi
		sriov_remove_vfs $nic_test 0
		sync_set server  vf_intf_garp_check_end
	fi
	return $result
}

sriov_test_bug_reproducer_2103801(){
	# https://bugzilla.redhat.com/show_bug.cgi?id=2103801#c24
	if i_am_server; then
		sync_set client sriov_test_bug_reproducer_2103801_start 14400
		if [ $? -ne 0 ]; then
			rlFail "sync timeout with client side!!!" && { return 1; }
		else
			sync_wait client sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "sync timeout with client side!!!"; return 1 ; }
		fi
	else
		sync_wait server sriov_test_bug_reproducer_2103801_start 14400 || { rlFail "sync timeout with server side!!!"; return 1 ; }
		local NIC_NUM=1
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[0]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		rlLog "got test nic is: ${test_iface}"
		local total_vfs=$(sriov_get_max_vf_from_pf ${test_iface})
		rlLog "got the total_vfs is: ${total_vfs}"
		local mac_perfix="$(get_mac_prefix $(hostname))01:" # MAC prefix used for VFs

		# find vf driver
		sriov_create_vfs ${test_iface} 0 1
		local check_vf_name=$(sriov_get_vf_iface ${test_iface} 0 1)
		local vf_driver_name=$(get_iface_driver $check_vf_name)
		if [ -z ${vf_driver_name} ]; then
			rlFail "can't find vf driver"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sync_set server sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "sync timeout with server side!!!"; return 1 ; }
		fi
		rlLog "vf driver is: ${vf_driver_name}"
		sriov_remove_vfs ${test_iface}
		if [ ! -d /sys/bus/pci/drivers/${vf_driver_name} ]; then
			sync_set server sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "can't find vf driver in sys file"; return 1 ; }
		fi
		# start test
		dmesg -C
		sriov_create_vfs ${test_iface} 0 ${total_vfs}
		for i in $(seq 1 ${total_vfs}); do
			local mac_suffix=$(printf "%02x" ${i})
			let ii=i-1
			ip link set ${test_iface} vf ${ii} mac ${mac_perfix}${mac_suffix} # Set VF mac address via PF
			local vf_bus_info=$(sriov_get_vf_bus_info ${test_iface} 0 ${i})
			echo "${vf_bus_info}" > /sys/bus/pci/drivers/${vf_driver_name}/unbind # unbind the VF from IAVF
		done
		sriov_remove_vfs ${test_iface}
		if [ $(dmesg | grep -c -i "Never saw reset") -ne 0 ]; then
			rlFail "got Never saw reset message on dmesg log"
		fi

		sync_set server sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "sync timeout with server side!!!"; return 1 ; }
	fi
}

sriov_test_vf_vlan_negative()
{

	#vlan negative testing, like setting vlan -1/0/4096
	#reproducer for bz1859477, run the command with the VF netdev, should just fail without a kernel panic
	local result=0
	local vid="-1 0 4096"

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vf_vlan_neg_start
		sync_wait client test_vf_vlan_neg_end

	else
		sync_wait server test_vf_vlan_neg_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_vlan_neg_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			rlFail "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf %02x ${ipaddr}):01:01
				ip link set $vf down
				sleep 2
			fi

			ip link set $vf up
			sleep 5
			for i in $vid;
			do
				rlRun "ip link set dev $nic_test vf 0 vlan $i" "0-255"
				sleep 2
				ip link show dev $nic_test
			done

			rlLog "reproducer for bz1859477, run the command with the VF netdev, should just fail without a kernel panic"
			rlRun "ip link set dev $vf vf 0 vlan 3" "1-255"

		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vf_vlan_neg_end
	fi

	return $result
}

sriov_test_vf_pf_speed_consistency()
{
	#reproducer for 1844598, vf speed and pf speed should be consistent
	local result=0
	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vf_pf_speed_start
		sync_wait client test_vf_pf_speed_end

	else
		sync_wait server test_vf_pf_speed_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_pf_speed_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			rlFail "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf %02x ${ipaddr}):01:01
				ip link set $vf down
				sleep 2
			fi

			ip link set $vf up
			sleep 5
			pf_speed=`ethtool $nic_test | grep -i 'speed' | grep -o '[0-9]\+'`
			rlLog "pf speed is $pf_speed"
			vf_speed=`ethtool $vf | grep -i 'speed' | grep -o '[0-9]\+'`
			rlLog "vf speed is $vf_speed"
			[ x"$pf_speed" != x"$vf_speed" ] && result=1

		fi

		sriov_remove_vfs $nic_test 0
		sync_set server test_vf_pf_speed_end
	fi

	return $result
}

sriov_test_bz2057244_vf_not_up()
{
	log_header "bz2057244" $result_file
	local result=0
	ip link set $nic_test up
	local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:02"
	local pktgen_dst_mac="00:de:ad:$(printf %02x $ipaddr):01:02"
	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test
		sync_set client test_bz2057244_start 14400
		if [ $? -eq 0 ]; then
			sync_wait client test_bz2057244_end 14400
			ip addr flush $nic_test
			sync_set client test_bz2057244_ns_start 14400
			if [ $? -eq 0 ]; then
				ip link add link $nic_test name $nic_test.3 type vlan id 3
				ip addr add 172.3.${ipaddr}.22/24 dev $nic_test.3
				ip link set $nic_test.3 up
				ip addr show
				sync_wait client test_bz2057244_ns_end 14400
				ip addr flush $nic_test.3
				ip link delete $nic_test.3
			else
				ip addr flush $nic_test.3
				ip link delete $nic_test.3
				rlFail "sync error with NS testing, need to check"
			fi
		else
			ip addr flush $nic_test
			rlFail "sync error with VM testing, need to check"
			exit 1
		fi
	else
		sync_wait server test_bz2057244_start 14400
		if [ $? -eq 0 ] && [ ! -f /tmp/sriov_test_bz2057244_with_vm ]; then
			rlLog "reproducer with VM for the bz2057244"
			touch /tmp/sriov_test_bz2057244_with_vm
			rlRun "ip link set ${nic_test} up"
			for loop in {1..10};do
				echo "######## loop $loop"
				rlRun "ip link set ${nic_test} promisc off"
				sriov_create_vfs $nic_test 0 1
				if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
					result=1
					echo "attach vf to vm failed"
				fi
				local vf=$(sriov_get_vf_iface $nic_test 0 1)
				cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST up}
					{ip addr flush \$NIC_TEST}
					{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
					{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
					{ip link show \$NIC_TEST}
					{ip addr show \$NIC_TEST}
					{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				ip link set $nic_test vf 0 trust on
				cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
					{ip link set \$NIC_TEST promisc on}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				cmd=(
					{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				rtn=$?
				if [ $rtn -ne 0 ];then
					rlFail "ping failed, check if vf could up"
					cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip link set \$NIC_TEST down}
						{ip link set \$NIC_TEST up}
						#check the iface link state
						{ip link show dev \$NIC_TEST}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					result=1
					break
				fi
				cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
					{ip link set \$NIC_TEST promisc off}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				cmd=(
					{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				rtn=$?
				if [ $rtn -ne 0 ];then
					rlFail "ping failed, check if vf could up"
					cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip link set \$NIC_TEST down}
						{ip link set \$NIC_TEST up}
						#check the iface link state
						{ip link show dev \$NIC_TEST}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					result=1
					break
				fi
				ip link set $nic_test vf 0 trust off
				cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
					{ip link set \$NIC_TEST promisc on}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				sriov_detach_vf_from_vm $nic_test 0 1 $vm1
				sriov_remove_vfs $nic_test 0
			done
			sync_set server test_bz2057244_end 14400

			if [ $? -eq 0 ] && [ ! -f /tmp/sriov_test_bz2057244_with_ns ]; then
				rm -rf /tmp/sriov_test_bz2057244_with_ns
				touch /tmp/sriov_test_bz2057244_with_ns
				sync_wait server test_bz2057244_ns_start 14400
				rlLog "reproducer with NS for the bz2057244"
				local pf_bus_info=$(sriov_get_pf_bus_info $nic_test 0)
				local total_vfs=$(cat /sys/bus/pci/devices/${pf_bus_info}/sriov_totalvfs)
				sriov_create_vfs $nic_test 0 1
				local vf=$(sriov_get_vf_iface $nic_test 0 1)
				for i in $(seq 1 100); do
					rlLog "start $i test"
					ip netns del bz2057244_ns1
					modprobe -r bridge
					sriov_remove_vfs $nic_test 0
					ip li > /dev/null
					if [[ ${total_vfs} -le 8 ]]; then
						sriov_create_vfs $nic_test 0 $total_vfs
					else
						sriov_create_vfs $nic_test 0 8
					fi
					sleep 5
					ip link show
					rlRun "ip link set $nic_test vf 0 vlan 3"
					ip netns add bz2057244_ns1
					ip link set dev $vf netns bz2057244_ns1
					ip netns exec bz2057244_ns1 ip link add dev br0 type bridge
					ip netns exec bz2057244_ns1 ip li set $vf master br0
					ip netns exec bz2057244_ns1 ip li set $vf up
					ip netns exec bz2057244_ns1 ip li set br0 up
					ip netns exec bz2057244_ns1 ip add flush br0
					ip netns exec bz2057244_ns1 ip add add 172.3.${ipaddr}.12/24 dev br0
					ip netns exec bz2057244_ns1 ip addr show
					ip netns exec bz2057244_ns1  ping 172.3.${ipaddr}.22 -c 5

					ip li set $nic_test vf 0 mac $mac
					ip netns exec bz2057244_ns1 ip li set $vf mac $mac
					ip netns exec bz2057244_ns1 ip li set br0 address $mac
					ip netns exec bz2057244_ns1 ip addr show
					ip netns exec bz2057244_ns1 timeout 30s bash -c "until ping 172.3.${ipaddr}.22 -c 5; do sleep 5; done"
					ip link set $nic_test vf 0 vlan 0
					ip link set $nic_test vf 0 trust on
					ip link set $nic_test vf 0 trust off
					ip link set $nic_test vf 0 trust on
					ip link set $nic_test vf 0 trust off
					ip link set $nic_test vf 0 trust on
					ip netns exec bz2057244_ns1 ip addr flush br0
					ip netns exec bz2057244_ns1 ip link add link br0 name br0.3 type vlan id 3
					ip netns exec bz2057244_ns1 ip li set br0.3 up
					sleep 5
					#Because the following 'ping command' is cancelled, comment the ip address configuration
					#ip netns exec bz2057244_ns1 ip add add 172.3.${ipaddr}.12/24 dev br0.3
					ip netns exec bz2057244_ns1 ip addr show
					#no need to ping to reproduce this bug,just check the iface state
					#ip netns exec bz2057244_ns1 timeout 60s bash -c "until ping 172.3.${ipaddr}.22 -c 5; do sleep 5; done"
					ip netns exec bz2057244_ns1 ip link set $vf down
					ip netns exec bz2057244_ns1 ip link set $vf up
					if [ $? -ne 0 ];then
						sleep 10
						ip netns exec bz2057244_ns1 ip link set $vf up
					fi
					sleep 3
					rlRun "ip netns exec bz2057244_ns1 ip link show dev $vf"
					rlRun "ip netns exec bz2057244_ns1 ip link show dev $vf |grep -w NO-CARRIER" 1 && break
					rlLog "finish $i test"
					rlLog "clean test configuration"
					sriov_remove_vfs $nic_test 0
				done
				sriov_remove_vfs $nic_test 0
				sync_set server test_bz2057244_ns_end 14400
				rm -rf /tmp/sriov_test_bz2057244_with_vm
				#remove the added netns
				ip netns del bz2057244_ns1
				# recover virbr0, because when "modeprobe -r bridge", virbr0 is removed
				modprobe -v bridge
				if ! ip link show virbr0; then
					virsh net-list --all
					virsh net-destroy default
					virsh net-autostart default
					virsh net-start default
					if (( $rhel_version < 9 )); then
						rlRun "systemctl restart libvirtd"
					else
						rlRun "systemctl restart virtnetworkd.service"
						rlRun "systemctl status virtqemud --no-pager -l"
					fi
					rlRun "virsh net-list --all"
					sleep 10
					rlRun "ip link show virbr0"
				fi
			else
				rm -rf /tmp/sriov_test_bz2057244_with_ns
				rlFail "sync error with NS testing"
				exit 1
			fi
		else
			rlFail "sync error with VM testing"
			rm -rf /tmp/sriov_test_bz2057244_with_vm
			exit 1
		fi
	fi
	return $result
}

#no need to run this testing because of bz2070917 is closed as NOTBUG
sriov_test_bz2070917_vlan_bridge_nic()
{
		log_header "bz2057244 vf donot work at vlan over bridge over NIC topology" $result_file
		local result=0
		ip link set $nic_test up
		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
		local pktgen_dst_mac="00:de:ad:$(printf %02x $ipaddr):01:02"

		if i_am_server; then
			ip addr flush $nic_test
			ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
			ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

			sync_set client test_bz2070917_start
		if [ $? -eq 0 ]; then
			sync_wait client test_bz2070917_end
			ip addr flush $nic_test
		else
			ip addr flush $nic_test
			rlFail "sync error need to check"
			exit 1
		fi
		else
			sync_wait server test_bz2070917_start
		if [ $? -eq 0 ]; then
			rlLog "reproducer with NS for the bz2070917"
			sriov_create_vfs $nic_test 0 1
			local vf=$(sriov_get_vf_iface $nic_test 0 1)

			ip netns add ns1
			ip link set $vf  netns ns1
			ip netns exec ns1 ip link set $vf up
			ip netns exec ns1 ip link add dev br0 type bridge
			ip netns exec ns1 ip link set $vf master br0
			ip netns exec ns1 ip link add link br0 name br0.3 type vlan id 3
			ip netns exec ns1 ip link set br0 up
			ip netns exec ns1 ip link set br0.3 up
			ip netns exec ns1 ip addr add 172.30.${ipaddr}.33/24 dev br0.3
			ip netns exec ns1 ip link show br0.3
			ip netns exec ns1 timeout 60s bash -c "until ping 172.30.${ipaddr}.2 -c 5; do sleep 5; done"
			ip netns exec ns1 ip link show
			ip netns exec ns1 timeout 60s bash -c "until ping 172.30.${ipaddr}.2 -c 5; do sleep 5; done" || \
				rlFail "ping remote server via br0.3 failed"
			ip netns delete ns1
			sriov_remove_vfs $nic_test 0
			sync_set server test_bz2070917_end
			result=1
		else
			rlFail "sync error with server"
			exit 1
		fi
		fi

		return $result
}

sriov_test_bz2055446_no_arp_reply()
{
	log_header "bz2055446" $result_file

	local result=0
	ipaddr=$(get_static_ip_subnet $SERVERS)
	mac_prefix=$(get_mac_prefix $SERVERS)

	ip link set $nic_test up

	if i_am_server; then

		rlRun "ip link add link ${nic_test} name ${nic_test}.3 type vlan id 3"
		rlRun "ip add add 172.3.$ipaddr.212/24 dev ${nic_test}.3"
		rlRun "ip link set ${nic_test}.3 up"
		sync_set client SERVER_DONE
		rlRun "ping -c 5 172.3.$ipaddr.211"
		sync_wait client CLIENT_DONE

		ip link del ${nic_test}.3
		ip addr flush $nic_test
	else
		local pf_bus_info=$(sriov_get_pf_bus_info $nic_test 0)
		local total_vfs=$(cat /sys/bus/pci/devices/${pf_bus_info}/sriov_totalvfs)
		if [[ ${total_vfs} -le 8 ]]; then
			sriov_create_vfs $nic_test 0 $total_vfs
		else
			sriov_create_vfs $nic_test 0 8
		fi
		local VF=$(sriov_get_vf_iface $nic_test 0 1)
		rlRun "sleep 3"
		#set vlan for vf
		rlRun "ip link set $nic_test vf 0 vlan 3"
		rlRun "ip netns add bz2055446_ns1"
		#attach vf to netns
		rlRun "ip link set dev $VF netns bz2055446_ns1"

		rlRun "ip netns exec bz2055446_ns1 ip link add dev br0 type bridge"
		rlRun "ip netns exec bz2055446_ns1 ip link set $VF master br0"
		rlRun "ip netns exec bz2055446_ns1 ip  link set $VF up"
		rlRun "ip netns exec bz2055446_ns1 ip link set br0 up"
		rlRun "ip netns exec bz2055446_ns1 ip add flush br0"
		rlRun "ip netns exec bz2055446_ns1 ip add add 172.3.$ipaddr.211/24 dev br0"

		rlRun "ip link set $nic_test vf 0 mac ${mac_prefix}14:66"
		rlRun "ip netns exec bz2055446_ns1  ip link set $VF address ${mac_prefix}14:66" "0-255"
		ip netns exec bz2055446_ns1 ip link show
		rlRun "ip netns exec bz2055446_ns1 ip link set br0 address ${mac_prefix}14:66"
		#clean up vf vlan
		rlRun "ip link set $nic_test vf 0 vlan 0"
		rlRun "ip netns exec bz2055446_ns1 ip add flush br0"
		rlRun "ip netns exec bz2055446_ns1 ip link add link br0 name br0.3 type vlan id 3"
		rlRun "ip netns exec bz2055446_ns1 ip link set br0.3 up"
		rlRun "ip netns exec bz2055446_ns1 ip add add 172.3.$ipaddr.211/24 dev br0.3"
		sync_wait server SERVER_DONE
		#check vf connection
		rlRun "ip netns exec bz2055446_ns1 ping -c 5 172.3.$ipaddr.212"
		rlRun "ip link set $nic_test vf 0 spoofchk off"
		#check vf connection with spoofchk off
		rlRun "ip netns exec bz2055446_ns1 ping -c 5 172.3.$ipaddr.212"
		sync_set server CLIENT_DONE

		#clean up
		ip netns del bz2055446_ns1
		sriov_remove_vfs $nic_test 0

	fi

	return $result
}

sriov_test_bz2071027_double_tagging()
{
	log_header "bz2071027" $result_file

	local result=0
	ipaddr=$(get_static_ip_subnet $SERVERS)
	ip link set $nic_test up
	iperf3_install

	if i_am_server; then
		rlRun "get_iface_sw_port $nic_test sw port" "0-255"
		if [  $sw = 93180 ] || [ $sw =  9364 ]; then
			# switch 9364 and 93180 don't support qinq as defualt , set it pass
			rlRun "swcfg qinq_config $sw $port"
		fi
		rlRun "ip link add link ${nic_test} name ${nic_test}.3 type vlan id 3"
		rlRun "ip link add link ${nic_test}.3 name ${nic_test}.3.3 type vlan id 3"
		rlRun "ip link add link ${nic_test}.3 name ${nic_test}.3.4 type vlan id 4"
		rlRun "ip link set ${nic_test}.3 up"
		rlRun "ip link set ${nic_test}.3.3 up"
		rlRun "ip link set ${nic_test}.3.4 up"
		rlRun "ip add add 172.10.${ipaddr}.11/24 dev ${nic_test}.3"
		rlRun "ip add add 172.3.${ipaddr}.11/24 dev ${nic_test}.3.3"
		rlRun "ip add add 172.4.${ipaddr}.11/24 dev ${nic_test}.3.4"
		rlRun "ip add add 2022:10:${ipaddr}::11/64 dev ${nic_test}.3"
		rlRun "ip add add 2022:103:${ipaddr}::11/64 dev ${nic_test}.3.3"
		rlRun "ip add add 2022:104:${ipaddr}::11/64 dev ${nic_test}.3.4"
		rlRun "iperf3 -s -p 50001 -V --logfile ./serverlog & "
		sync_set client SERVER_DONE
		sync_wait client CLIENT_DONE
		#clean up
		if [  $sw = 93180 ] || [ $sw =  9364 ]; then
			# clean up switch qinq config
			rlRun "swcfg qinq_delete $sw $port"
		fi
		rlRun "pkill iperf3"
		rlRun "ip link del ${nic_test}.3.3"
		rlRun "ip link del ${nic_test}.3.4"
		rlRun "ip link del ${nic_test}.3"

	else
		rlRun "get_iface_sw_port $nic_test sw port" "0-255"
		if [  $sw = 93180 ] || [ $sw =  9364 ]; then
			# switch 9364 and 93180 don't support qinq as defualt , set it pass
			rlRun "swcfg qinq_config $sw $port"
		fi
		sriov_create_vfs ${nic_test} 0 1
		sleep 3
		local VF=$(sriov_get_vf_iface $nic_test 0 1)
		rlRun "ip netns add bz2071027_ns1"
		rlRun "ip link set $VF netns bz2071027_ns1"
		rlRun "ip link set ${nic_test} vf 0 vlan 3"
		rlRun "ip netns exec bz2071027_ns1 ip link add link $VF name $VF.3 type vlan id 3"
		rlRun "ip netns exec bz2071027_ns1 ip link add link $VF name $VF.4 type vlan id 4"
		rlRun "ip netns exec bz2071027_ns1 ip add add 172.10.${ipaddr}.10/24 dev $VF"
		rlRun "ip netns exec bz2071027_ns1 ip add add 172.3.${ipaddr}.10/24 dev $VF.3"
		rlRun "ip netns exec bz2071027_ns1 ip add add 172.4.${ipaddr}.10/24 dev $VF.4"
		rlRun "ip netns exec bz2071027_ns1 ip add add 2022:10:${ipaddr}::10/64 dev $VF"
		rlRun "ip netns exec bz2071027_ns1 ip add add 2022:103:${ipaddr}::10/64 dev $VF.3"
		rlRun "ip netns exec bz2071027_ns1 ip add add 2022:104:${ipaddr}::10/64 dev $VF.4"
		rlRun "ip netns exec bz2071027_ns1 ip link set $VF up"
		rlRun "ip netns exec bz2071027_ns1 ip link set $VF.3 up"
		rlRun "ip netns exec bz2071027_ns1 ip link set $VF.4 up"
		sync_wait server SERVER_DONE
		rlRun "ip netns exec bz2071027_ns1 ping 172.10.${ipaddr}.11 -c 5"
		rlRun "ip netns exec bz2071027_ns1 ping 172.3.${ipaddr}.11 -c 5"
		rlRun "ip netns exec bz2071027_ns1 ping 172.4.${ipaddr}.11 -c 5"

		rlRun "ip netns exec bz2071027_ns1 ping6 2022:10:${ipaddr}::11 -c 5 "
		rlRun "ip netns exec bz2071027_ns1 ping6 2022:103:${ipaddr}::11 -c 5 "
		rlRun "ip netns exec bz2071027_ns1 ping6 2022:104:${ipaddr}::11 -c 5 "
		rlRun "ip netns exec bz2071027_ns1 ping6 2022:104:${ipaddr}::11 -c 5 "
		rlRun "do_host_iperf3 172.10.${ipaddr}.11 2022:10:${ipaddr}::11  result.log  bz2071027_ns1 $VF '-p 50001'"
		rlRun "do_host_iperf3 172.3.${ipaddr}.11 2022:103:${ipaddr}::11  result.log  bz2071027_ns1 $VF '-p 50001'"
		rlRun "do_host_iperf3 172.4.${ipaddr}.11 2022:104:${ipaddr}::11  result.log  bz2071027_ns1 $VF '-p 50001'"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 172.10.${ipaddr}.11 -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 172.3.${ipaddr}.11 -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 172.4.${ipaddr}.11 -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 2022:10:${ipaddr}::11  -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 2022:103:${ipaddr}::11  -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 2022:104:${ipaddr}::11  -p 50001"
		sync_set server CLIENT_DONE

		#clean up
		if [  $sw = 93180 ] || [ $sw =  9364 ]; then
			# clean up switch qinq config
			rlRun "swcfg qinq_delete $sw $port"
		fi
		rlRun "ip netns exec bz2071027_ns1 ip link del $VF.3"
		rlRun "ip netns exec bz2071027_ns1 ip link del $VF.4"
		rlRun "ip netns del bz2071027_ns1"
		sriov_remove_vfs $nic_test 0
	fi

	return $result
}

sriov_test_bz2080033_re_assign_MACs_to_VFs()
{
	log_header "bz2080033 assign a MAC that is already assigned to a different VF" $result_file
	ip link set $nic_test up
	local MAC1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local MAC2="00:de:ad:$(printf %02x $ipaddr):01:02"

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz2080033_start
		if [ $? -eq 0 ]; then
			sync_wait client test_bz2080033_end
			ip addr flush $nic_test
		else
			ip addr flush $nic_test
			rlFail "sync error need to check"
			exit 1
		fi
	else
		sync_wait server test_bz2080033_start
		if [ $? -eq 0 ]; then
			rlLog "reproducer for the bz2080033"
			sriov_create_vfs $nic_test 0 2
			local VF1=$(sriov_get_vf_iface $nic_test 0 1)
			local VF2=$(sriov_get_vf_iface $nic_test 0 2)
			rlRun "ip link set $nic_test vf 0 mac $MAC1"
			rlRun "ip link set $nic_test vf 1 mac $MAC2"
			rlRun "ip link show dev $nic_test | grep 'vf 0'| grep '$MAC1'"
			rlRun "ip link show dev $nic_test | grep 'vf 1'| grep '$MAC2'"
			rlRun "ip link set $nic_test vf 0 mac $MAC2"
			rlRun "ip link show dev $nic_test | grep 'vf 0'|grep '$MAC2'"
			rlRun "ip link set $nic_test vf 1 mac $MAC1"
			rlRun "ip link show dev $nic_test | grep 'vf 1'|grep '$MAC1'"
			rlRun "dmesg | tail -10"
			sync_set server test_bz2080033_end
			sriov_remove_vfs $nic_test 0

		else
			rlFail "sync error with server"
			exit 1
		fi
	fi

}

sriov_test_bz2134294_change_MTU_under_load()
{
	log_header "bz2134294_change_MTU_under_load" $result_file
	ip link set $nic_test up
	local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz2134294_start
		if [ $? -eq 0 ]; then
			sync_wait client test_bz2134294_end
			ip addr flush $nic_test
		else
			ip addr flush $nic_test
			rlFail "sync error need to check"
			exit 1
		fi
	else
		sync_wait server test_bz2134294_start
		if [ $? -eq 0 ]; then
			rlLog "reproducer for the bz2134294"
			sriov_create_vfs $nic_test 0 2
			local VF1=$(sriov_get_vf_iface $nic_test 0 1)
			ip link set $VF1 up
			ip addr flush $VF1
			ip addr add 172.30.${ipaddr}.11/24 dev $nic_test
			rlRun "ping 172.30.${ipaddr}.2 -c 5"
			rlLog "netperf -H 172.30.${ipaddr}.2 -l 100 &"
			netperf -H 172.30.${ipaddr}.2 -l 100 &
			for i in 1280 1500 2000 900 ; do
				sleep 5
				#rlRun "ip link set $nic_test mtu $i"
				rlRun "ifconfig $VF1 mtu $i"
				sleep 1
			done
			sleep 100
			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
				result=1
			else
				local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.111/24 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
				{netperf -H 172.30.${ipaddr}.2 -l 100 \&}
				{ip link set \$NIC_TEST mtu 1280}
				{ip link set \$NIC_TEST mtu 1500}
				{ip link set \$NIC_TEST mtu 2000}
				{ip link set \$NIC_TEST mtu 5000}
				{ip link set \$NIC_TEST mtu 9000}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				result=$?

				sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			fi


			sync_set server test_bz2134294_end
			sriov_remove_vfs $nic_test 0

		else
			rlFail "sync error with server"
			exit 1
		fi
	fi

}

sriov_test_bz2138215()
{
	$dbg_flag
	test_name=sriov_test_bz2138215
	log_header "$test_name" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/${nic_test}/accept_ra"
		rlRun "ip link add link ${nic_test} name ${nic_test}.3 type vlan id 3"
		rlRun "ip link add link ${nic_test} name ${nic_test}.4 type vlan id 4"
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/${nic_test}.3/accept_ra"
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/${nic_test}.4/accept_ra"
		rlRun "ip addr flush $nic_test"
		rlRun "ip addr flush ${nic_test}.3"
		rlRun "ip addr flush ${nic_test}.4"
		rlRun "ip addr add 2021:db8:${ipaddr}:1002::5/64 dev ${nic_test}.3"
		rlRun "ip addr add 2021:db8:${ipaddr}:1105::5/64 dev ${nic_test}.4"
		rlRun "ip link set ${nic_test}.3 up"
		rlRun "ip link set ${nic_test}.4 up"

		sync_wait client ${test_name}_start
		rlRun "ip neighbour del 2021:db8:${ipaddr}:1002::4 dev ${nic_test}.3" 0-255
		rlRun "ping -c 10 2021:db8:${ipaddr}:1002::4"
		test $? -eq 0 && sync_set client "pass" || sync_set client "fail"

		rlRun "ip addr flush $nic_test"
		rlRun "ip link del ${nic_test}.3"
		rlRun "ip link del ${nic_test}.4"
		rlRun "echo 1 > /proc/sys/net/ipv6/conf/${nic_test}/accept_ra"
	else
		rlRun "ovs_install"

		rlRun "sriov_create_vfs $nic_test 0 2"

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if sriov_vfmac_is_zero $nic_test 0 1; then
			ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
			#workaround for ionic bz1914175
			ip link set dev $vf address 00:de:ad:$(printf "%02x" $ipaddr):01:01
			ip link set $vf down
			sleep 2
		fi

		rlRun "ip link set ${nic_test} up"
		rlRun "ip link add link ${nic_test} name ${nic_test}.3 type vlan id 3"
		rlRun "ip link set ${nic_test}.3 up"
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/${nic_test}/accept_ra"
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/${nic_test}.3/accept_ra"
		rlRun "ip addr flush ${nic_test}"
		rlRun "ip addr flush ${nic_test}.3"

		local rhel_version=$(cut -f1 -d. /etc/redhat-release | sed 's/[^0-9]//g')
		if [[ $rhel_version -lt 7 ]]; then
			rlRun "service start openvswitch"
		else
			rlRun "systemctl start openvswitch.service"
		fi
		rlRun "ovs-vsctl add-br sriov-ovs-br0"
		rlRun "ovs-vsctl add-port sriov-ovs-br0 ${nic_test}.3"
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/sriov-ovs-br0/accept_ra"
		rlRun "ip addr flush sriov-ovs-br0"
		rlRun "ip addr add 2021:db8:${ipaddr}:1002::4/64 dev sriov-ovs-br0"
		rlRun "ip link set sriov-ovs-br0 up"
		rlRun "ip link set ${nic_test} vf 0 vlan 4"
		rlRun "ip link set $vf up"
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/${vf}/accept_ra"
		rlRun "ip addr flush ${vf}"
		rlRun "sleep 1"
		rlRun "ip addr add 2021:db8:${ipaddr}:1105::4/64 dev ${vf}"
		rlRun "sleep 1"
		rlRun "ip addr show dev ${vf}"

		sync_set server ${test_name}_start
		rlRun "sync_wait_choice server 'pass' 'fail'"
		result=$?

		# cleanup
		rlRun "ip addr flush $vf"
		rlRun "ovs-vsctl del-br sriov-ovs-br0"
		if (($rhel_version <= 6)); then
			rlRun "service openvswitch stop"
		else
			rlRun "systemctl stop openvswitch.service"
		fi
		rlRun "echo 0 > /proc/sys/net/ipv6/conf/${nic_test}/accept_ra"
		rlRun "ip link del ${nic_test}.3"

		rlRun "sriov_remove_vfs $nic_test 0"
	fi

	return $result
}


sriov_test_bz2171382()
{
	test_name=sriov_test_bz2171382
	log_header "$test_name" $result_file
	local result=0
	local bz2138215_vid=3
	local server_ip4="192.3.${ipaddr}.1"
	local server_ip6="2021:db30:${ipaddr}:2345::1"
	local client_vf1_ip4="192.3.${ipaddr}.100"
	local client_vf1_ip6="2021:db30:${ipaddr}:2345::100"
	local client_vf2_ip4="192.3.${ipaddr}.101"
	local client_vf2_ip6="2021:db30:${ipaddr}:2345::101"
	local ip4_mask_len="24"
	local ip6_mask_len="64"


	ip link set $nic_test up

	if i_am_server; then

		ip link add link $nic_test name $nic_test.$bz2138215_vid type vlan id $bz2138215_vid
		ip link set $nic_test.$bz2138215_vid up
		ip add add $server_ip4/$ip4_mask_len dev $nic_test.$bz2138215_vid
		ip add add $server_ip6/$ip6_mask_len dev $nic_test.$bz2138215_vid
		sync_set client server_conf_done
		rlRun "ping $client_vf1_ip4 -c 5 -I  $nic_test.$bz2138215_vid"
		rlRun "ping $client_vf1_ip6 -c 5 -I  $nic_test.$bz2138215_vid"
		sync_wait client ping_start
		ping $client_vf1_ip4 -c 50 -I $nic_test.$bz2138215_vid
		ping $client_vf1_ip6 -c 50 -I $nic_test.$bz2138215_vid
		sync_set client ping_done
		ip link delete $nic_test.$bz2138215_vid
		ip add flush $nic_test
		sync_wait client test_done
	else

		rlRun "sriov_create_vfs $nic_test 0 2"

		local vf1=$(sriov_get_vf_iface $nic_test 0 1)
		local vf2=$(sriov_get_vf_iface $nic_test 0 2)

		ip link set $nic_test vf 0 spoofchk off trust on vlan $bz2138215_vid
		ip link set $nic_test vf 1 spoofchk off trust on vlan $bz2138215_vid
		ip netns add ns1
		ip netns add ns2
		ip link set $vf1 netns ns1
		ip link set $vf2 netns ns2
		ip netns exec ns1 ip link set $vf1 up
		ip netns exec ns2 ip link set $vf2 up
		ip netns exec ns1 ip add add $client_vf1_ip4/$ip4_mask_len dev $vf1
		ip netns exec ns1 ip add add $client_vf1_ip6/$ip6_mask_len dev $vf1
		ip netns exec ns2 ip add add $client_vf2_ip4/$ip4_mask_len dev $vf2
		ip netns exec ns2 ip add add $client_vf2_ip6/$ip6_mask_len dev $vf2
		sync_wait server server_conf_done
		rlRun "ip netns exec ns1 ping $server_ip4 -c 5 -I $vf1 "
		rlRun "ip netns exec ns1 ping $server_ip6 -c 5 -I $vf1 "
		rlRun "ip netns exec ns2 ping $server_ip4 -c 5 -I $vf2 "
		rlRun "ip netns exec ns2 ping $server_ip6 -c 5 -I $vf2 "
		sync_set server ping_start
		ip netns exec ns1 tcpdump -i $vf1 -w ns1_$vf1.pcap &
		ip netns exec ns2 tcpdump -i $vf2 -w ns2_$vf2.pcap &
		sync_wait server ping_done
		pkill tcpdump
		sleep 2
		rlRun "tcpdump -r ns1_$vf1.pcap -ne|grep ICMP|grep '$server_ip4'"
		rlRun "tcpdump -r ns2_$vf2.pcap -ne|grep ICMP|grep '$server_ip4'" "1-255"
		rlRun "tcpdump -r ns2_$vf2.pcap -ne|grep ICMP|grep '$server_ip6'|grep 'echo request'" "1-255"
		rlRun "tcpdump -r ns2_$vf2.pcap -ne|grep ICMP|grep '$server_ip6'|grep 'echo reply'" "1-255"
		sync_set server test_done
		ip netns delete ns1
		ip netns delete ns2
		rm -rf ns1_$vf1.pcap ns2_$vf2.pcap
		modprobe -r 8021q
		sriov_remove_vfs $nic_test 0

	fi

	return $result
}
