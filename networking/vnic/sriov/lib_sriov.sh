#!/bin/bash

# helper for SR-IOV

# create VFs for PF
#
# *** NOTE:
# sriov_create_vfs() must be called before any VF is attached to VM
# becasue for some kind of NIC, to create new VF, the driver must be unloaded, therefore
# the created VF will be remvoed and this could incur issue
[ -e ./lib_mlx.sh ] && source ./lib_mlx.sh
[ -e ./lib_chelsio.sh ] && source ./lib_chelsio.sh
[ -e ./lib_nfp.sh ] && source ./lib_nfp.sh

function RUN_CMD
{
	echo "RUN_CMD: $1"
	eval "$1"
}

sriov_create_vfs()
{
	$dbg_flag
	local PF=$1
	local iPF=$2 # index of PCI dev, start from 0. For some NICs, VF is independent of PF, like cxgb4
	local num_vfs=$3

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	ip link set $PF up

	echo ----------------------
	lspci -s ${pf_bus_info}
	echo ----------------------
	case ${driver} in
		mlx4_en)
			if [ -e lib_mlx.sh ];then
				mlx_create_vfs "$@"
			else
				echo "no lib for mellanox"
				return 1
			fi
			;;
		cxgb4)
			if [ -e lib_chelsio.sh ];then
				chelsio_create_vfs "$@"
			else
				echo "no lib for chelsio"
				return 1
			fi
			;;
		mlx5_core)
			if [ -e lib_mlx.sh ];then
				mlx_create_vfs "$@"
			else
				echo "no lib for mellanox"
				return 1
			fi
			;;
		*)
			echo ${num_vfs} > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
				sleep 5

			lspci -s ${pf_bus_info} -vvv | grep -i vf
				echo ----------------------

				if (( $(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | wc -l) != ${num_vfs} )); then
					echo "FAIL to create VFs"
					return 1
				fi

				ip link set $PF up
				ip link show $PF
			;;
	esac
	link_up_ifs_with_same_bus $pf_bus_info
}

#create vfs via "echo ${num_vfs} > /sys/class/net/$PF/device/sriov_numvfs "
sriov_create_vfs_1()
{
	local PF=$1
	local iPF=$2 # index of PCI dev, start from 0. For some NICs, VF is independent of PF, like cxgb4
	local num_vfs=$3

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	ip link set $PF up

	echo ----------------------
	lspci -s ${pf_bus_info}
	echo ----------------------
	case ${driver} in
		mlx4_en)
			if [ -e lib_mlx.sh ];then
				mlx_create_vfs_1 "$@"
			else
				echo "no lib for mellanox"
				return 1
			fi
			;;
		cxgb4)
			if [ -e lib_chelsio.sh ];then
				chelsio_create_vfs "$@"
			else
				echo "no lib for chelsio"
				return 1
			fi
			;;
		mlx5_core)
			if [ -e lib_mlx.sh ];then
					mlx_create_vfs_1 "$@"
			else
					echo "no lib for mellanox"
					return 1
			fi
			;;
		*)
			echo ${num_vfs} > /sys/class/net/$PF/device/sriov_numvfs
				sleep 5

			lspci -s ${pf_bus_info} -vvv | grep -i vf
			echo ----------------------
			if (( $(ls -l /sys/class/net/$PF/device/virtfn* | wc -l) != ${num_vfs} )); then
				echo "FAIL to create VFs"
				return 1
			fi

			ip link set $PF up
			ip link show $PF
			;;
	esac
	link_up_ifs_with_same_bus $pf_bus_info
}

# remove VFs for PF
sriov_remove_vfs()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')
	ip link set $PF up

	echo ----------------------
	lspci -s ${pf_bus_info}
	echo ----------------------
	case ${driver} in
		mlx4_en)
			mlx_remove_vfs "$@"
			;;
		cxgb4)
			chelsio_remove_vfs "$@"
			;;
				mlx5_core)
			mlx_remove_vfs "$@"
			;;

		*)
			echo 0 > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
				sleep 5

			lspci -s ${pf_bus_info} -vvv | grep -i vf
				echo ----------------------

				if (($(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* 2>/dev/null | wc -l) != 0)); then
					echo "FAIL to remove VFs"
					return 1
				fi

				ip link set $PF down
				sleep 2
				ip link set $PF up
				ip link show $PF
			;;
	esac
}

# attach VF to VM, one for each calling
sriov_attach_vf_to_vm()
{
	$dbg_flag
	local PF=$1
	local iPF=$2 	# start from 0.
					# For cxgb4, PF used to create VF is different from the original PF
	local iVF=$3 	# index of vf, starting from 1
	local vm=$4
	local mac=$5
	local vlan=$6

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	link_up_ifs_with_same_bus $pf_bus_info

	case ${driver} in
		cxgb4)
			chelsio_attach_vf_to_vm "$@"
			return $?
			;;
	esac

	local vf_bus_info=$(ls -lv /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
	local vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')
	local domain=$(echo $vf_bus_info | awk -F '[:|.]' '{print $1}')
	local bus=$(echo $vf_bus_info | awk -F '[:|.]' '{print $2}')
	local slot=$(echo $vf_bus_info | awk -F '[:|.]' '{print $3}')
	local function=$(echo $vf_bus_info | awk -F '[:|.]' '{print $4}')

	if [ "$SRIOV_USE_HOSTDEV" = "yes" ]; then
		rlRun "ip link set $PF vf $(($iVF-1)) mac $mac"
		cat <<-EOF > ${vf_nodedev}.xml
			<hostdev mode='subsystem' type='pci' managed='yes'>
				<source>
					<address domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
				</source>
			</hostdev>
		EOF
	else
		if [ -n "$vlan" ]; then
			cat <<-EOF > ${vf_nodedev}.xml
				<interface type='hostdev' managed='yes'>
					<source>
						<address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
					</source>
					<mac address='${mac}'/>
					<vlan>
						<tag id='${vlan}'/>
					</vlan>
				</interface>
			EOF
		else
			# workaround for bz1215975
			echo "$(ethtool -i $PF | grep 'driver:' | awk '{print $2}')"
			if [ $(ethtool -i $PF | grep 'driver:' | awk '{print $2}') == 'qlcnic' ]; then
				echo "ectring workaround for bz1215975 chooise"
				cat <<- EOF > ${vf_nodedev}.xml
					<interface type='hostdev' managed='yes'>
						<source>
							<address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
						</source>
						<mac address='${mac}'/>
							<vlan>
								<tag id='4095'/>
							</vlan>
					</interface>
					EOF
			else
				cat <<- EOF > ${vf_nodedev}.xml
					<interface type='hostdev' managed='yes'>
						<driver name='vfio'/>
						<source>
							<address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
						</source>
						<mac address='${mac}'/>
					</interface>
					EOF
			fi
		fi
	fi

	# print out xml file
	echo "Printing out ${vf_nodedev}.xml..."
	cat ${vf_nodedev}.xml

	if virsh attach-device $vm ${vf_nodedev}.xml ; then
		RUN_CMD "virsh dumpxml ${vm} | grep -A 10 \"domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'\" |\
				grep -v \"domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'\" |\
				grep -m 1 'address'"
		if virsh dumpxml ${vm} | grep -A 10 "domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'" &>/dev/null
		then
			local guest_vf_bus=$(virsh dumpxml ${vm} | grep -A 10 "domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'" |\
					grep -v "domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'" |\
					grep -m 1 'address' |\
					sed -n "s/.*bus='0x\([[:alnum:]]\+\)'.*/\1/p")
			local guest_vf_slot=$(virsh dumpxml ${vm} | grep -A 10 "domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'" |\
					grep -v "domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'" |\
					grep -m 1 'address' |\
					sed -n "s/.*slot='0x\([[:alnum:]]\+\)'.*/\1/p")
			local guest_vf_function=$(virsh dumpxml ${vm} | grep -A 10 "domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'" |\
					grep -v "domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'" |\
					grep -m 1 'address' |\
					sed -n "s/.*function='0x\([[:alnum:]]\+\)'.*/\1/p")
			vmsh run_cmd ${vm} "lspci | grep ${guest_vf_bus}:${guest_vf_slot}.${guest_vf_function}"
			for((guest_vf_timeout=1;guest_vf_timeout<=5;guest_vf_timeout++)); do
				if vmsh run_cmd ${vm} "ip link show | grep \$(grep PCI_SLOT_NAME /sys/class/net/*/device/uevent | grep ${guest_vf_bus}:${guest_vf_slot}.${guest_vf_function} | sed 's/\/sys\/class\/net\/\(.*\)\/device\/uevent.*/\1/g') &>/dev/null"; then
					break
				else
					echo "wait interface ${guest_vf_timeout} sec" && sleep 1
				fi
				if [ "${guest_vf_timeout}" -eq 5 ]; then
					echo "wait for ${guest_vf_timeout} sec still can not find interface"
					return 1
				fi
			done
			return 0
		else
			return 1
		fi
	fi
	return 1
}

# detach VF from VM, one for each calling
sriov_detach_vf_from_vm()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of vf, starting from 1
	local vm=$4

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			mlx_detach_vf_from_vm "$@"
			return $?
			;;
		cxgb4)
			chelsio_detach_vf_from_vm "$@"
			return $?
			;;
		*)
	local vf_bus_info=$(ls -lv /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
		local vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')

	# fix rt-kernel can't detach vf Bug 1887895
#	if [[ $ENABLE_RT_KERNEL != "yes" ]]; then
		virsh detach-device $vm ${vf_nodedev}.xml
#	else
#		local rhel_version=$( cat /etc/redhat-release | sed  's/\(.*\)\([0-9].[0-9]\)\(.*\)/\2/g')
#		if [[ $(echo "${rhel_version} > 8.6" | bc) -eq 1 ]]; then
#			virsh detach-device $vm ${vf_nodedev}.xml
#		else
#			virsh detach-device $vm ${vf_nodedev}.xml
#			virsh shutdown $vm
#			sleep 10
#			virsh start $vm
#			sleep 10
#			local vm_status=$(virsh list --all | grep -w $vm |  awk '{print $3,$4}' | tr -d " ")
#			rlLog "${vm} in ${vm_status} status"
#			if [[ x"${vm_status}" != x"running" ]]; then
#				virsh destroy $vm
#				sleep 10
#				virsh start $vm
#				sleep 10
#				local vm_status=$(virsh list --all | grep -w $vm |  awk '{print $3,$4}' | tr -d " ")
#				rlLog "current ${vm} in ${vm_status} status"
#				return 0
#			fi
#		fi
#	fi

	#workaround for arch system https://gitlab.com/libvirt/libvirt/-/issues/72
	if [ "$SYS_ARCH" == "aarch" ];then
		sleep 5
	fi
		;;
	esac
}

sriov_attach_pf_to_vm()
{
	local PF=$1
	local vm=$2

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')
		local pf_nodedev=pci_$(echo $pf_bus_info | sed 's/[:|.]/_/g')

	link_up_ifs_with_same_bus $pf_bus_info

	local domain=$(echo $pf_bus_info | awk -F '[:|.]' '{print $1}')
	local bus=$(echo $pf_bus_info | awk -F '[:|.]' '{print $2}')
	local slot=$(echo $pf_bus_info | awk -F '[:|.]' '{print $3}')
	local function=$(echo $pf_bus_info | awk -F '[:|.]' '{print $4}')

	cat <<-EOF > ${pf_nodedev}.xml
		<hostdev mode='subsystem' type='pci' managed='yes'>
			<source>
				<address domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
			</source>
		</hostdev>
	EOF
	if virsh attach-device $vm ${pf_nodedev}.xml; then
		return 0
	fi
	return 1
}

sriov_detach_pf_from_vm()
{
	local pf_bus_info=$1
	local vm=$2
	local pf_nodedev=pci_$(echo $pf_bus_info | sed 's/[:|.]/_/g')
	local domain=$(echo $pf_bus_info | awk -F '[:|.]' '{print $1}')
	local bus=$(echo $pf_bus_info | awk -F '[:|.]' '{print $2}')
	local slot=$(echo $pf_bus_info | awk -F '[:|.]' '{print $3}')
	local function=$(echo $pf_bus_info | awk -F '[:|.]' '{print $4}')
	# fix rt-kernel can't detach vf

	# virsh detach-device $vm ${vf_nodedev}.xml
	# fix rt-kernel can't detach vf Bug 1887895
	if [[ $ENABLE_RT_KERNEL != "yes" ]]; then
			virsh detach-device $vm ${pf_nodedev}.xml
			return 0
	else
		local rhel_version=$( cat /etc/redhat-release | sed  's/\(.*\)\([0-9].[0-9]\)\(.*\)/\2/g')
		if [[ $(echo "${rhel_version} > 8.6" | bc) -eq 1 ]]; then
			virsh detach-device $vm ${pf_nodedev}.xml
		else
			virsh detach-device $vm ${pf_nodedev}.xml
			virsh shutdown $vm
			sleep 10
			virsh start $vm
			sleep 10
			local vm_status=$(virsh list --all | grep -w $vm |  awk '{print $3,$4}' | tr -d " ")
			rlLog "${vm} in ${vm_status} status"
			if [[ x"${vm_status}" != x"running" ]]; then
				virsh destroy $vm
				sleep 10
				virsh start $vm
				sleep 10
				local vm_status=$(virsh list --all | grep -w $vm |  awk '{print $3,$4}' | tr -d " ")
				rlLog "current ${vm} in ${vm_status} status"
				return 0
			fi
		fi
	fi
	return 1
}

# get vf interface
sriov_get_vf_iface()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of VF, starting from 1

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			echo $(mlx_get_vf_iface "$@")
			;;
		cxgb4)
			echo $(chelsio_get_vf_iface "$@")
			;;
		*)
						[ -f /sys/bus/pci/devices/"${pf_bus_info}"/virtfn$((iVF-1)) ] || let result++
			local vf_bus_info=$(ls -l /sys/bus/pci/devices/"${pf_bus_info}"/virtfn$((iVF-1)) | awk '{print $NF}' | sed 's/..\///')

				local vf_iface=()
				local cx=0
				while [ -z "$vf_iface" ] && (($cx < 60)); do
					sleep 1
					vf_iface=($(ls /sys/bus/pci/devices/${vf_bus_info}/net 2>/dev/null))
					let cx=cx+1
				done

				echo ${vf_iface[0]}
			;;
	esac
}

# check if vf mac is 00:00:00:00:00:00
sriov_vfmac_is_zero()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of VF, starting from 1


	local vf_iface=$(sriov_get_vf_iface $PF $iPF $iVF)

	local vfmac=$(cat /sys/class/net/${vf_iface}/address)
	if [ "$vfmac" = "00:00:00:00:00:00" ]; then
		return 0
	fi

	return 1
}

sriov_get_vf_bus_info()
{
	local PF=$1
	local iPF=$2
	local iVF=$3

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			local vf_bus_info=$(mlx_get_vf_bus_info "$@")
			rtn=$?
			echo ${vf_bus_info}
			return $rtn
			;;
		cxgb4)
			local vf_bus_info=$(chelsio_get_vf_bus_info "$@")
			rtn=$?
			echo ${vf_bus_info}
			return $rtn
			;;
		*)
			local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
			rtn=$?
			echo ${vf_bus_info}
			return $rtn
			;;
		esac
}

sriov_get_pf_bus_info()
{
	local PF=$1
	local iPF=$2

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			pf_bus_info=$(mlx_get_pf_bus_info "$@")
			echo $pf_bus_info
			;;
		cxgb4)
			pf_bus_info=$(chelsio_get_pf_bus_info "$@")
			echo $pf_bus_info
			;;
		*)
			echo $pf_bus_info
			;;
		esac
}

get_all_ifs_with_same_bus()
{
	bus=$1
	result=""

	for ifname in $(ip link | grep "mtu" | awk '{ print $2 }' | sed 's/://g')
	do
		if [ "$ifname" = "lo" ];then
			continue
		fi
			bus_info=$(ethtool -i $ifname|grep bus-info|awk -F" " '{print $2}')
			if [ "$bus" = "$bus_info" ];then
				result+=" $ifname"
			fi
	done

	echo $result
}

link_up_ifs_with_same_bus()
{
	bus=$1
	dual_ports=$(get_all_ifs_with_same_bus $bus)
	for port in $dual_ports
	do
		ip link set $port up
	done
}

vm_netperf_ipv4()
{
	local vm=$1
	local ipv4=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -L "$1 } else { print $1 } }')
	local p_ipv4=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -I "$1 } else { print $1 } }')

	local log=""

	# IPv4
	vmsh run_cmd $vm "timeout 120s bash -c \"until ping -c3 $p_ipv4; do sleep 10; done\"" > /tmp/perf.log
	if [ $? -eq 0 ];then
			vmsh run_cmd $vm "netperf -4 -t UDP_STREAM -H $ipv4 -l 30 -- -m 10000" > /tmp/perf.log
			if (( $? )); then
				UDP_STREAMv4=0
			else
				UDP_STREAMv4=$(cat /tmp/perf.log|sed -n '/netperf/,/^\[root@.*]#/ {/.*/ p}'|sed -n '/\(\b[0-9]\+\)\{5,\}/ p'|sed 's/[\r\n]//'|tail -n1|awk '{printf $NF}')
			fi
	fi

	echo $UDP_STREAMv4
}

vm_netperf_ipv6()
{
		local vm=$1
		local ipv6=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -L "$1 } else { print $1 } }')
		local p_ipv6=$(echo $2 | awk -F ',' '{ if (NF > 1) { print $2" -I "$1 } else { print $1 } }')

		local log=""

		# IPv4
		vmsh run_cmd $vm "timeout 120s bash -c \"until ping6 -c3 $p_ipv6; do sleep 10; done\"" > /tmp/perf.log
		if [ $? -eq 0 ];then
			vmsh run_cmd $vm "netperf -6 -t UDP_STREAM -H $ipv6 -l 30 -- -m 10000" > /tmp/perf.log
			if (( $? )); then
				UDP_STREAMv6=0
			else
				UDP_STREAMv6=$(cat /tmp/perf.log|sed -n '/netperf/,/^\[root@.*]#/ {/.*/ p}'|sed -n '/\(\b[0-9]\+\)\{5,\}/ p'|sed 's/[\r\n]//'|tail -n1|awk '{printf $NF}')
			fi
		fi
		echo $UDP_STREAMv6
}

switchdev_get_reps()
{
#	if [ "$NIC_MODEL" == "Netronome-Device_4000" ]; then
#		local PF=$1
#		local vfs_num=$(cat /sys/class/net/$PF/device/sriov_numvfs)
#		local count
#		for count in $(seq 0 $((vfs_num-1))); do
#			local iface
#			for iface in $(ls /sys/devices/virtual/net/); do
#				dmesg | grep -q "VF$count Representor($iface)" || continue
#				local ifaces=$ifaces' '$iface
#			done
#		done
#	else
#		local PF=$1
#		local phys_switch_id=$(cat /sys/class/net/$PF/phys_switch_id 2>/dev/null)
#		local iface
#		for iface in $(ls /sys/devices/virtual/net/); do
#			local phys_switch_id1=$(cat /sys/devices/virtual/net/$iface/phys_switch_id 2>/dev/null)
#			[ -z "$phys_switch_id1" ] && continue
#			[ "$phys_switch_id1" != "$phys_switch_id" ] && continue
#			echo $ifaces | grep -qw $iface && continue
#			local ifaces=$ifaces' '$iface
#		done
#	fi
#	echo -n $ifaces
		local PF=$1
		declare -A ifaces_map
		local phys_switch_id=$(cat /sys/class/net/$PF/phys_switch_id 2>/dev/null)
		local iface
		for iface in /sys/class/net/*/; do
			iface=${iface%*/}
			iface=${iface##*/}
			local phys_switch_id1=$(cat /sys/class/net/$iface/phys_switch_id 2>/dev/null)
			local phys_switch_id1=$(cat /sys/class/net/$iface/phys_switch_id 2>/dev/null)
			[ -z "$phys_switch_id1" ] && continue
			[ "$phys_switch_id1" != "$phys_switch_id" ] && continue
			# Provided by "Alaa Hleihel" <ahleihel@redhat.com> start
			# ignore non-VF Representors
			local phys_port_name1=$(cat /sys/class/net/$iface/phys_port_name 2>/dev/null)
			case "$phys_port_name1" in
				*pf*vf*) ;;
				*) continue;;
			esac
			# Provided by "Alaa Hleihel" <ahleihel@redhat.com> stop
			local item
			# shellcheck disable=SC2068 # Add double quotes would break this code
			for item in ${ifaces_map[@]}; do
				[ "$iface" == "$item" ] && continue 2
			done
			ifaces_map["$phys_port_name1"]="$iface"
		done
		# shellcheck disable=SC2068 # Add double quotes would break this code
		local keys=($(echo ${!ifaces_map[@]} | tr " " "\n" | sort | tr "\n" " "))
		local key; local ifaces=();
		# shellcheck disable=SC2068 # Add double quotes would break this code
		for key in ${keys[@]}; do
			ifaces+=(${ifaces_map[$key]})
		done
		# shellcheck disable=SC2068 # Add double quotes would break this code
		echo -n ${ifaces[@]}

}

switchdev_setup_nfp()
{
	if [ "$NIC_MODEL" == "Netronome-Device_4000" ]; then
		echo "change the fw to enable switchdev mode"
		nfp_change_fw_sw
		timeout 120s bash -c "until ip link set $nic_test up &>/dev/null; do sleep 1; done"
	fi

}

switchdev_setup_mlx()
{
	if [ "$NIC_DRIVER" == "mlx5_core" ];then
		local vf1=$(sriov_get_vf_iface $nic_test 0 1)
		local vf_id1=$(sriov_get_vf_bus_info $nic_test 0 1)
		local pf_id1=$(sriov_get_pf_bus_info $nic_test 0)

		echo "############enable SR-IOV switchdev mode############"
		echo "########unbind vf from pf##########"
		echo $vf_id1 > /sys/bus/pci/drivers/$NIC_DRIVER/unbind
		ip link show
		echo "########setting switchdev mode#######"
		devlink dev eswitch set pci/$pf_id1 mode switchdev
		devlink dev eswitch show pci/$pf_id1
		echo "########bind vf to pf##########"
		echo $vf_id1 > /sys/bus/pci/drivers/$NIC_DRIVER/bind
		sleep 5
		ip link show
	fi
}

switchdev_cleanup_mlx()
{
	if [ "$NIC_DRIVER" == "mlx5_core" ];then
		local vf1=$(sriov_get_vf_iface $nic_test 0 1)
		local vf_id1=$(sriov_get_vf_bus_info $nic_test 0 1)
		local pf_id1=$(sriov_get_pf_bus_info $nic_test 0)
		echo $vf_id1 > /sys/bus/pci/drivers/$NIC_DRIVER/unbind
		ip link show
		devlink dev eswitch set pci/$pf_id1 mode legacy
		devlink dev eswitch show pci/$pf_id1
		echo $vf_id1 > /sys/bus/pci/drivers/$NIC_DRIVER/bind
		sleep 5
		ip link show
	fi

}
switchdev_setup_ice()
{
	if [ "$NIC_DRIVER" == "ice" ];then
		local pf_id1=$(sriov_get_pf_bus_info $nic_test 0)
		devlink dev eswitch set pci/$pf_id1 mode switchdev
		devlink dev eswitch show pci/$pf_id1
		ip link show
	fi
}

switchdev_cleanup_ice()
{
	if [ "$NIC_DRIVER" == "ice" ];then
		local pf_id1=$(sriov_get_pf_bus_info $nic_test 0)
		devlink dev eswitch set pci/$pf_id1 mode legacy
		devlink dev eswitch show pci/$pf_id1
		ip link show
	fi
}

clear_dmesg_message()
{
	rlRun -l "dmesg -C"
	return 0
}

check_call_trace()
{
	rlRun -l "dmesg | grep -C 100 'WARNING'" 1
	rlRun -l "dmesg | grep -C 100 -i 'Call Trace'" 1
	rlRun -l "dmesg | grep -C 100 -i 'cut here'" 1
	rlRun -l "dmesg | grep -C 100 -i 'Kernel panic'" 1
	rlRun -l "dmesg | grep -C 100 -i BUG" 1
	rlRun -l "dmesg | grep -C 100 -i 'failed to load firmware image'" 1
	#bz1825389 bz1796517
	rlRun -l "dmesg | grep $NIC_DRIVER | grep 'probe of' | grep 'failed with error'" 1
	#bz1831401
	rlRun -l "dmesg | grep -C 100 'firmware error detected'" 1
	#bz1750856 bz1668912
	rlRun -l "dmesg | grep -C 100 -i 'Unit Hang'" 1
	#bz1785158
	rlRun -l "dmesg | grep -C 100 'hw csum failure'" 1
	#bz1750856 bz1668912
	rlRun -l "dmesg | grep -C 100 -i 'Detected Tx Unit Hang'" 1
	return 0
}

sriov_attach_vf_to_cnt()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of VF, starting from 1
	local container=$4
	local vf=$(sriov_get_vf_iface $PF $iPF $iVF)
	local containerID=$(podman ps | grep $container | awk '{print $1}')
	#echo "containerID $containerID"
	local nsID=$(podman inspect -f '{{.State.Pid}}' $containerID)
	ln -bs /proc/$nsID/ns/net /var/run/netns/$nsID
	ip link set $vf netns $nsID
	#link up vf
	podman exec $container ip link set $vf up
	if podman exec $container ip link show | grep $vf ; then
		return 0
	else
		return 1
	fi
}

sriov_get_max_vf_from_pf()
{
	local PF=$1
	local iPF=$2
	local pf_bus_info=$(sriov_get_pf_bus_info ${PF} ${iPF})
	# Check the legitimacy of the pci address
	if [[ ${pf_bus_info} =~ [0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F] ]]
	then
		local pf_bus_info="${pf_bus_info}"
	else
		return 1
	fi
	local total_vfs=$(cat /sys/bus/pci/devices/${pf_bus_info}/sriov_totalvfs)
	if [ -z ${total_vfs} ]; then
		return 1
	else
		echo $total_vfs
		return 0
	fi
}

workaround_swtpm()
{
	# https://github.com/stefanberger/swtpm/issues/284
	if ! cat /etc/libvirt/qemu.conf | grep "swtpm_user" | grep -v "#" | grep -q root;then
		sed -i '/swtpm_user.*tss/d' /etc/libvirt/qemu.conf
		echo 'swtpm_user = "root"' >> /etc/libvirt/qemu.conf;
		if (($(rpm -E %rhel) < 7)); then
			service libvirtd restart
		else
			systemctl restart libvirtd
			systemctl restart virtlogd.socket
		fi
	fi
}

rmnicdriver()
{
	local driver=${1:-"$NIC_DRIVER"}
	local retval=0
	[ x"$driver" == x ] && return 0
	set_all_test_nic_down
	local dependlib=`lsmod | grep ^$driver | awk 'NF>=4{print $4}'`
	local libs=$(echo $dependlib | tr ',' ' ')
	if [ x$NIC_DRIVER == x'nicvf' ];then
		libs="$libs nicpf"
	elif [ x$NIC_DRIVER == x'cxgb4' ];then
		libs="$libs csiostor"
	fi
	for lib in $libs;
	do
		modprobe -rv $lib
	done
	modprobe -rv $driver
	rlRun "udevadm settle"
	unset driver
	return $retval
}

remodprobe_driver()
{
	local driver=${1:-"$NIC_DRIVER"}
	local retval=0
	[ x"$driver" == x ] && return 0
	rmnicdriver $driver
	retval=$?
	[ $retval -ne 0 ] && return $retval
	sleep 5
	if [ x$NIC_DRIVER == x'nicvf' ];then
		modprobe -v nicpf
	elif [ x$NIC_DRIVER == x'cxgb4' ];then
		modprobe -v csiostor
		modprobe -v $driver
	else
		modprobe -v $driver
	fi
	retval=$?
	rlRun "udevadm settle"
	unset driver
	return $retval
}

set_all_test_nic_down()
{
	local target_driver=${1:-"$NIC_DRIVER"}
	[ x"${target_driver}" == x ] && { echo "test nic driver not be specified, exit!!!"; return 0; }
	local default_nic=$(ip route | awk '/default/ {print $5}' | awk 'NR==1 {print}')
	for find_nic in /sys/class/net/*; do
		local find_dev=$(basename ${find_nic})
		if [[ x"${find_dev}" == x"${default_nic}" ]] || [[ x"${i}" == x"lo" ]]; then
			continue
		fi
		local find_driver=$(readlink ${find_nic}/device/driver/module)
		if [ -n "${find_driver}" ]; then
			local find_driver=$(basename ${find_driver})
			if [[ x"${find_driver}" == x"${target_driver}" ]]; then
				ip link set ${find_dev} down
			fi
		fi
	done
}
