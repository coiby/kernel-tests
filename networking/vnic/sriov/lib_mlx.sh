#!/bin/bash
mlx_create_vfs()
{
	local PF=$1
	local iPF=$2 # index of PCI dev, start from 0. For some NICs, VF is independent of PF, like cxgb4
	local num_vfs=$3

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			# FIX_ME if new NIC is introduced.
			# Both Mellanox-MT26448 and Mellanox-MT27500 and Mellanox-MT27520 are dual-port
			# Because it don't support to add dual-port VFs to the same bonding, so we want to only create single port VF here
			# If need, please add code to test dual-port VFs
			num_vfs="$num_vfs,$num_vfs,0"
			if ! grep CMDLINE_OPTS /etc/modprobe.d/libmlx4.conf 2> /dev/null; then
				echo 'install mlx4_core /sbin/modprobe --ignore-install mlx4_core  $CMDLINE_OPTS && (if [ -f /usr/libexec/mlx4-setup.sh -a -f /etc/rdma/mlx4.conf ]; then /usr/libexec/mlx4-setup.sh < /etc/rdma/mlx4.conf; fi; /sbin/modprobe mlx4_en; /sbin/modprobe mlx4_ib)' > /etc/modprobe.d/libmlx4.conf
			fi
			modprobe -r mlx4_en; modprobe -r mlx4_ib;  modprobe -r mlx4_core
			modprobe mlx4_core num_vfs=${num_vfs} probe_vf=${num_vfs}
		;;
		mlx5_core)
			load_openibd_for_mlnx
			if [ -e /sys/class/infiniband ];then
				pushd /sys/class/infiniband 1>/dev/null
				local dir_name=$(ls -al | grep $pf_bus_info | sed "s/.*\///")
				pushd ./${dir_name}/device 1>/dev/null
				if [ -f mlx5_num_vfs ];then
					echo ${num_vfs} > mlx5_num_vfs
				elif [ -f sriov_numvfs ];then
					echo ${num_vfs} > sriov_numvfs
				fi
				popd 1>/dev/null
				popd 1>/dev/null
			else
				echo ${num_vfs} > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
			fi
		;;
	esac

		sleep 5

		lspci | grep -i ether
		echo ----------------------

		if (( $(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | wc -l) != ${num_vfs} )); then
				echo "FAIL to create VFs"
				return 1
		fi

		ip link set $PF up
		ip link show $PF
}

mlx_create_vfs_1()
{
	local PF=$1
	local iPF=$2 # index of PCI dev, start from 0. For some NICs, VF is independent of PF, like cxgb4
	local num_vfs=$3

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	echo ${num_vfs} > /sys/class/net/$PF/device/sriov_numvfs

	sleep 5

	lspci | grep -i ether
	echo ----------------------

	if (( $(ls -l /sys/class/net/$PF/device/virtfn* | wc -l) != ${num_vfs} )); then
		echo "FAIL to create VFs"
		return 1
	fi

	ip link set $PF up
	ip link show $PF
}

mlx_remove_vfs()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	case ${driver} in
		mlx4_en)
			modprobe -r mlx4_en; modprobe -r mlx4_ib;  modprobe -r mlx4_core
			modprobe mlx4_core
			modprobe mlx4_en
		;;
		mlx5_core)
			if [ -e /sys/class/infiniband ];then
				pushd /sys/class/infiniband 1>/dev/null
				local dir_name=$(ls -al | grep $pf_bus_info | sed "s/.*\///")
				pushd ./${dir_name}/device 1>/dev/null
				if [ -f mlx5_num_vfs ];then
						echo 0 > mlx5_num_vfs
				elif [ -f sriov_numvfs ];then
						echo 0 > sriov_numvfs
				fi
				popd 1>/dev/null
				popd 1>/dev/null
			else
				echo 0 > /sys/bus/pci/devices/${pf_bus_info}/sriov_numvfs
			fi
		;;
	esac

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

mlx_attach_vf_to_vm()
{
	echo "mlx_attach_vf_to_vm"
}

mlx_detach_vf_from_vm()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of vf, starting from 1
	local vm=$4

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	iVF=$((iPF + iVF))

	local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
	local vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')

	if virsh detach-device $vm ${vf_nodedev}.xml; then
			sleep 5
	fi

}

mlx_get_vf_iface()
{
	local PF=$1
	local iPF=$2 # start from 0. For some NICs, VF is independent of PF, like cxgb4
	local iVF=$3 # index of VF, starting from 1

	local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	iVF=$((iPF + iVF))

	local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)

	local vf_iface=()
	local cx=0
	while [ -z "$vf_iface" ] && (($cx < 60)); do
			sleep 1

			vf_iface=($(ls /sys/bus/pci/devices/${vf_bus_info}/net 2>/dev/null))
			let cx=cx+1
	done

	echo ${vf_iface[0]}

}

mlx_get_vf_bus_info()
{
	  local PF=$1
	  local iPF=$2
	  local iVF=$3

	  local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	  local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	  local vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
	  rtn=$?
	  echo ${vf_bus_info}
	  return $rtn

}

mlx_get_pf_bus_info()
{
	  local PF=$1
	  local iPF=$2

	  local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
	  local pf_bus_info=$(ethtool -i $PF | grep 'bus-info'| sed 's/bus-info: //')

	  echo $pf_bus_info
}

load_openibd_for_mlnx()
{
	if [ -f /etc/init.d/openibd ];then
		echo "openibd has benn installed"
		/etc/init.d/openibd restart
		return $?
	fi
}

