#!/bin/bash
# shellcheck disable=SC1083,SC2050,SC2207,SC2034,SC2128
# In lib_chelsio.sh line 172:
#						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
#                                                ^-- SC1083: This { is literal. Check expression (missing ;/\n?) or quote it.
#                                                        ^-------------^ SC2191: The = here is literal. To assign by index, use ( [index]=value ) with no spaces. To keep as literal, quote it.
#                                                                                          ^--^ SC2206: Quote to prevent word splitting, or split robustly with mapfile or read -a.
#                                                                                                                                                          ^-- SC1083: This } is literal. Check expression (missing ;/\n?) or quote it.


#In lib_chelsio.sh line 173:
#						{echo 0 \> /proc/sys/net/ipv6/conf/\$\{NIC_TEST\}/accept_dad}
#                                                ^-- SC1083: This { is literal. Check expression (missing ;/\n?) or quote it.
#                                                                                                            ^-- SC1083: This } is literal. Check expression (missing ;/\n?) or quote it.


#In lib_chelsio.sh line 174:
#						{echo 0 \> /proc/sys/net/ipv6/conf/\$\{NIC_TEST\}/dad_transmits}
#                                                ^-- SC1083: This { is literal. Check expression (missing ;/\n?) or quote it.
#                                                                                                               ^-- SC1083: This } is literal. Check expression (missing ;/\n?) or quote it.

chelsio_create_vfs()
{
	local PF=$1
		local iPF=$2 # index of PCI dev, start from 0. For some NICs, VF is independent of PF, like cxgb4
		local num_vfs=$3

		local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

		# FIX_ME if new NIC is introduced.
		# For Chelsio T5/T4 adapters, the physical functions are currently assigned as:
		# Physical functions 0 - 3: for the SR-IOV functions of the adapter
		# Physical function 4: for all NIC functions of the adapter
		# Physical function 5: for iSCSI
		# Physical function 6: for FCoE
		# Physical function 7: Currently not assigned
		# --- "Chelsio T5/T4 Unified Wire for Linux - Installation and User's Guide
		#
		local RHEL_VERSION=$(cat /etc/redhat-release | awk  '{print $7}')
		#if [ $RHEL_VERSION = "6.9" ];then
		if [ "xxx" = "xxx" ];then
			   pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")
			   echo ${num_vfs} > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
		else
			   local sriov_numvfs[0]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.0/")/sriov_numvfs)
			   local sriov_numvfs[1]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.1/")/sriov_numvfs)
			   local sriov_numvfs[2]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.2/")/sriov_numvfs)
			   local sriov_numvfs[3]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.3/")/sriov_numvfs)
			   sriov_numvfs[$iPF]=$num_vfs
			   num_vfs="${sriov_numvfs[0]},${sriov_numvfs[1]},${sriov_numvfs[2]},${sriov_numvfs[3]}"
			   # workaround for bz1191046
			   if [ ! -f /etc/modprobe.d/cxgb4.conf ] || ! grep CMDLINE_OPTS /etc/modprobe.d/cxgb4.conf 2> /dev/null; then
					   echo 'install cxgb4 /sbin/modprobe --ignore-install cxgb4 $CMDLINE_OPTS && /sbin/modprobe iw_cxgb4' > /etc/modprobe.d/cxgb4.conf
			   fi
			   # workaround for bz1205092
			   if [ ! -f /etc/modprobe.d/libcxgb4.conf ] || ! grep CMDLINE_OPTS /etc/modprobe.d/libcxgb4.conf 2> /dev/null; then
					   echo 'install cxgb4 /sbin/modprobe --ignore-install cxgb4 $CMDLINE_OPTS && /sbin/modprobe iw_cxgb4' > /etc/modprobe.d/libcxgb4.conf
			   fi
			   modprobe -r iw_cxgb4; modprobe -r cxgb4
			   modprobe cxgb4 num_vf=${num_vfs}
			   # workaround for bz1250931
			   sleep 5
			  rmmod cxgb4vf; modprobe cxgb4vf
			  pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")
	   fi

	   sleep 5

	   lspci | grep -i ether
	   echo ----------------------

	   if (( $(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | wc -l) != ${num_vfs} )); then
			   echo "FAIL to create VFs"
			   return 1
	   fi

	   for((ivf=1;ivf<=$num_vfs;ivf++))
	   do
			   vf_name=$(sriov_get_vf_iface $PF $iPF $ivf)
			   echo 0 > /proc/sys/net/ipv6/conf/${vf_name}/accept_dad
			   echo 0 > /proc/sys/net/ipv6/conf/${vf_name}/dad_transmits
	   done
	   #https://bugzilla.redhat.com/show_bug.cgi?id=1529064#c5
	   ethtool --set-priv-flags $PF port_tx_vm_wr on

	   ip link set $PF up
	   ip link show $PF
}

chelsio_remove_vfs()
{
	local PF=$1
		local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4

		local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

		local RHEL_VERSION=$(cat /etc/redhat-release | awk  '{print $7}')
		echo "RHEL_VERSION: $RHEL_VERSION"
		#if [ $RHEL_VERSION = "6.9" ];then
		if [ "xxx" = "xxx" ];then
			   pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")
			   echo 0 > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
		else
			   local sriov_numvfs[0]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.0/")/sriov_numvfs)
			   local sriov_numvfs[1]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.1/")/sriov_numvfs)
			   local sriov_numvfs[2]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.2/")/sriov_numvfs)
			   local sriov_numvfs[3]=$(cat /sys/bus/pci/devices/$(echo $pf_bus_info | sed "s/\..*$/\.3/")/sriov_numvfs)
			   sriov_numvfs[$iPF]=0
			   num_vfs="${sriov_numvfs[0]},${sriov_numvfs[1]},${sriov_numvfs[2]},${sriov_numvfs[3]}"
			   modprobe -r iw_cxgb4; modprobe -r cxgb4
			   modprobe cxgb4 num_vf=${num_vfs}
			   pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")
		fi

		sleep 5

		lspci | grep -i ether
		echo ----------------------

		if (($(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* 2>/dev/null | wc -l) != 0)); then
				echo "FAIL to remove VFs"
				return 1
		fi

		ip link set $PF down
		sleep 2
		ip link set $PF up
		ip link show $PF
}

chelsio_attach_vf_to_vm()
{
		local PF=$1
		local iPF=$2 # start from 0.
					 # For cxgb4, PF used to create VF is different from the original PF
		local iVF=$3 # index of vf, starting from 1
		local vm=$4
		local mac=$5
		local vlan=$6

		local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		#local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')
	local pf_bus_info=$(chelsio_get_pf_bus_info $PF $iPF)

	local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sort | sed -n ${iVF}p)
		local vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')
		local domain=$(echo $vf_bus_info | awk -F '[:|.]' '{print $1}')
		local bus=$(echo $vf_bus_info | awk -F '[:|.]' '{print $2}')
		local slot=$(echo $vf_bus_info | awk -F '[:|.]' '{print $3}')
		local function=$(echo $vf_bus_info | awk -F '[:|.]' '{print $4}')

		if [ "$SRIOV_USE_HOSTDEV" = "yes" ]; then
		local management_port=$(ls /sys/bus/pci/devices/${pf_bus_info}/net)
				ip link set $management_port vf $(($iVF-1)) mac $mac
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
						cat <<- EOF > ${vf_nodedev}.xml
				<interface type='hostdev' managed='yes'>
					<source>
						<address type='pci' domain='0x${domain}' bus='0x${bus}' slot='0x${slot}' function='0x${function}'/>
					</source>
					<mac address='${mac}'/>
				</interface>
			EOF
		fi
	fi

		if virsh attach-device $vm ${vf_nodedev}.xml; then
				sleep 5
				local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{echo 0 \> /proc/sys/net/ipv6/conf/\$\{NIC_TEST\}/accept_dad}
						{echo 0 \> /proc/sys/net/ipv6/conf/\$\{NIC_TEST\}/dad_transmits}
				)
				vmsh cmd_set $vm "${cmd[*]}"
				return 0
		fi
		return 1
}

chelsio_detach_vf_from_vm()
{
	local PF=$1
		local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
		local iVF=$3 # index of vf, starting from 1
		local vm=$4

		local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")

		local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sort | sed -n ${iVF}p)
		local vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')

		if virsh detach-device $vm ${vf_nodedev}.xml; then
				sleep 5
		fi
}

chelsio_get_vf_iface()
{
	local PF=$1
		local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
		local iVF=$3 # index of VF, starting from 1

		local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

		pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")

		local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sort | sed -n ${iVF}p)

		local vf_iface=()
		local cx=0
		while [ -z "$vf_iface" ] && (($cx < 60)); do
				sleep 1

				vf_iface=($(ls /sys/bus/pci/devices/${vf_bus_info}/net 2>/dev/null))
				let cx=cx+1
		done

		echo ${vf_iface[0]}

}

chelsio_get_vf_bus_info()
{
	  local PF=$1
	  local iPF=$2
	  local iVF=$3

	  local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	  local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	  pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")

	  local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sort | sed -n ${iVF}p)
	  rtn=$?
	  echo ${vf_bus_info}
	  return $rtn

}

chelsio_get_pf_bus_info()
{
	  local PF=$1
	  local iPF=$2

	  local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	  local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	  pf_bus_info=$(echo $pf_bus_info | sed "s/\..*$/\.$iPF/")
	  echo $pf_bus_info
}
