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

				sriov_detach_vf_from_vm $nic_test 0 1 $vm1
				sriov_remove_vfs $nic_test 0
				sync_set server test_bz2057244_end 14400

				if [ $? -eq 0 ] && [ ! -f /tmp/sriov_test_bz2057244_with_ns ]; then
					rm -rf /tmp/sriov_test_bz2057244_with_ns
					touch /tmp/sriov_test_bz2057244_with_ns
					sync_wait server test_bz2057244_ns_start 14400
					rlLog "reproducer with NS for the bz2057244"
					local pf_bus_info=$(sriov_get_pf_bus_info $nic_test 0)
					local total_vfs=$(cat /sys/bus/pci/devices/${pf_bus_info}/sriov_totalvfs)
					if [[ ${total_vfs} -le 8 ]]; then
						sriov_create_vfs $nic_test 0 $total_vfs
					else
						sriov_create_vfs $nic_test 0 8
					fi
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
						ip netns exec bz2057244_ns1 ip add add 172.3.${ipaddr}.12/24 dev br0.3
						ip netns exec bz2057244_ns1 ip addr show
						#no need to ping to reproduce this bug,just check the iface state
						#ip netns exec bz2057244_ns1 timeout 60s bash -c "until ping 172.3.${ipaddr}.22 -c 5; do sleep 5; done"
						rlRun "ip netns exec bz2057244_ns1 ip link set $vf down"
						rlRun "ip netns exec bz2057244_ns1 ip link set $vf up"
						sleep 5
						rlRun "ip netns exec bz2057244_ns1 ip link show dev $vf"
						rlRun "ip netns exec bz2057244_ns1 ip link show dev $vf |grep -w NO-CARRIER" 1 && break
						rlLog "finish $i test"
						rlLog "clean test configuration"
						sriov_remove_vfs $nic_test 0
					done
					sriov_remove_vfs $nic_test 0
					sync_set server test_bz2057244_ns_end 14400
					rm -rf /tmp/sriov_test_bz2057244_with_vm
				else
					rm -rf /tmp/sriov_test_bz2057244_with_ns
					rm -rf /tmp/sriov_test_bz2057244_with_vm
					rlFail "sync error with NS testing"
					exit 1
				fi
			else
				rlFail "sync error with VM testing"
				rm -rf /tmp/sriov_test_bz2057244_with_ns
				rm -rf /tmp/sriov_test_bz2057244_with_vm
				exit 1
			fi
		fi

		return $result
}

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
		rlRun "ip netns exec bz2055446_ns1  ip link set $VF address ${mac_prefix}14:66" "0 255"
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
		modprobe -r bridge
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
		rlRun "pkill iperf3"
		rlRun "ip link del ${nic_test}.3.3"
		rlRun "ip link del ${nic_test}.3.4"
		rlRun "ip link del ${nic_test}.3"

		else
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

		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 172.10.${ipaddr}.11 -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 172.3.${ipaddr}.11 -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 172.4.${ipaddr}.11 -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 2022:10:${ipaddr}::11  -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 2022:103:${ipaddr}::11  -p 50001"
		rlRun "ip netns exec bz2071027_ns1 iperf3 -c 2022:104:${ipaddr}::11  -p 50001"
		sync_set server CLIENT_DONE

		#clean up
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

