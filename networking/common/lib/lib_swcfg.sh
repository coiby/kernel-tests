#!/bin/bash -
# shellcheck disable=SC2034,SC1090,SC2154,SC2128

# ${NETWORK_COMMONLIB_DIR} is only used in Red hat netowrk-qe lab
# which would never be defined in partner's lab

#if [[ ! ${NETWORK_COMMONLIB_DIR+x} ]]
#then

rpm -q epel-release &>/dev/null || yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sshpass -V &>/dev/null || yum -y install sshpass

#
# entry function for switch configration
# the format:
#    swcfg sw_conf switch_name "switch_port_list" param1 param2 ...
#
swcfg()
{
	local sw_conf=$1
	local sw_name=$2
	local sw_port=$3

	echo ----------------------------------------------
	echo "$FUNCNAME" "$@"
	echo ----------------------------------------------

	echo sw_conf=$sw_conf
	echo sw_name=$sw_name
	echo sw_port=$sw_port

	if [ -z "$sw_conf" ] || [ -z "$sw_name" ] || [ -z "$sw_port" ]
	then
		echo "ERROR: invalid swcfg calling!"
		return 1
	fi
	wget http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/share/tools/lib_swcfg_list.sh -P $(dirname ${BASH_SOURCE[0]})/
	source $(dirname ${BASH_SOURCE[0]})/lib_swcfg_list.sh

	shift 3

	local sw_os=$(grep -e "^[[:blank:]]*${sw_name}[[:blank:]]\+" <<<"${swlist}" | head -n1 | awk '{print $2}')
	local sw_url=$(grep -e "^[[:blank:]]*${sw_name}[[:blank:]]\+" <<<"${swlist}" | head -n1 | awk '{print $3}')
	local sw_pw=$(grep -e "^[[:blank:]]*${sw_name}[[:blank:]]\+" <<<"${swlist}" | head -n1 | awk '{print $4}')

	echo sw_os=$sw_os
	echo sw_url=$sw_url
	echo sw_pw=$sw_pw

	if [[ -f "$(dirname ${BASH_SOURCE[0]})/lib_swcfg_api_${sw_os}.sh" ]]
	then
		source $(dirname ${BASH_SOURCE[0]})/lib_swcfg_api_${sw_os}.sh
	else
		echo "ERROR: Unsupported switch \"$sw_name\" with \"$sw_os\"!"
		return 1
	fi

	local cmd=''
	local VAR_IFACE=''

	# real implementation for each configuration
	case "$sw_conf" in
		setup )
			# swcfg setup $sw_name $sw_port
			eval "cmd=\"${cmd}${cmd_setup_global}\""
			for VAR_IFACE in $sw_port
			do
				eval "cmd=\"${cmd}${cmd_setup_for_each_port}\""
			done
			;;
		port_up )
			# swcfg port_up $sw_name $sw_port
			for VAR_IFACE in $sw_port
			do
				eval "cmd=\"${cmd}${cmd_port_up}\""
			done
			;;
		port_down )
			# swcfg port_down $sw_name $sw_port
			for VAR_IFACE in $sw_port
			do
				eval "cmd=\"${cmd}${cmd_port_down}\""
			done
			;;
		setup_port_channel )
			# swcfg setup_port_channel $sw_name "$sw_port" "$lacp_mode"
			#local VAR_BONDING_ID=$(tr -d '[a-zA-Z]' <<< "$sw_port" | tr ' ' '\n' | sed -e 's|/\([0-9]\)$|/0\1|' | tr -d '/' | sed 's/^0*//' | sort -nu | head -n1)
			local VAR_BONDING_ID=$SW_BONDING_ID
			local VAR_LACP_MODE=$1

			eval "cmd=\"$cmd_new_bonding_iface\""
			for VAR_IFACE in $sw_port
			do
				eval "cmd=\"${cmd}${cmd_add_slave_to_bonding}\""
			done
			eval "cmd=\"${cmd}${cmd_check_bonding_status}\""
			;;
		cleanup_port_channel )
			# swcfg cleanup_port_channel $sw_name "$sw_port"
			#local VAR_BONDING_ID=$(tr -d '[a-zA-Z]' <<< "$sw_port" | tr ' ' '\n' | sed -e 's|/\([0-9]\)$|/0\1|' | tr -d '/' | sed 's/^0*//' | sort -nu | head -n1)
			local VAR_BONDING_ID=$SW_BONDING_ID
			local VAR_LACP_MODE=$1

			for VAR_IFACE in $sw_port
			do
				eval "cmd=\"${cmd}${cmd_remove_slave_from_bonding}\""
			done
			eval "cmd=\"${cmd}${cmd_remove_bonding_interface}\""
			eval "cmd=\"${cmd}${cmd_check_bonding_status}\""
			;;
		* )
			echo "Unsupported switch config \"$sw_cfg\"!"
			return 1
	esac

	echo "-------------------------"
	printf "${cmd}\n"
	echo "-------------------------"
	sshpass -p $sw_pw ssh -o UserKnownHostsFile=/dev/null -o 'StrictHostKeyChecking=no' $sw_url <<<"$cmd"
}


#swcfg setup 5010 "e1/9 e1/10"
#swcfg setup 4550-3 "xe-0/0/28 xe-0/0/29"
#swcfg port_up 3750 "e1/9 e1/10"
#swcfg port_up 5010 "e1/9 e1/10"
#swcfg port_down 5010 "e1/9 e1/10"

#swcfg setup_port_channel 5010 "e1/9 e1/10" passive
#swcfg cleanup_port_channel 5010 "e1/9 e1/10"

#swcfg setup_port_channel 4550-3 "xe-0/0/28 xe-0/0/29" passive
#swcfg cleanup_port_channel 4550-3 "xe-0/0/28 xe-0/0/29"

###############################################################################

#
# bonding test, like lacp needs a switch connected to linux machine
# and bonding settings are needed in the switch
# helper functions below are used in the test to setup switch
#
# so, if bonding test are enabled
# ADAPTING FUNCTIONS BELOW TO YOUR TEST ENVIRONMENT IS A MUST
#   get_iface_sw_port()
#   swcfg_port_up_by_linux_iface()
#   swcfg_port_down_by_linux_iface()
#   swcfg_setup_bonding_by_linux_ifaces()
#   swcfg_cleanup_bonding_by_linux_ifaces()

#
# get_iface_sw_port
#   is to get the connected switch port by linux interface
#   and set the used switch name to $swname
#   set the switch port list to $swport
#
#   THE FUNCTION IS ONLY USED IN PARTNER'S LAB
#
# @parameters
#   INPUT
#     $1: list of linux network interfaces to query for the switch ports
#   OUTPUT
#     $2: bash variable to save switch name
#     $3: bash variable to save the list of switch ports
#
# This function is used only by functions below in this file
# No need to implement it if functions below don't use it
#
# Example
# get_iface_sw_port 'eth1 eth2' swname swport
#

get_iface_sw_port()
{
	local list_of_ifaces=$1
	local nic=($NIC_TEST)
	local swp=($SW_PORT)
	local list_of_swports=''

	for iface in $list_of_ifaces
	do
		for ((i=0; i<$(wc -w <<< $NIC_TEST); i++))
		do
		if [ "${nic[i]}" = "$iface" ]
		then
			[ -z "$list_of_swports" ] && list_of_swports="${swp[i]}" || list_of_swports="${list_of_swports} ${swp[i]}"
			break
		fi
		done
	done
	eval "$2=$SW_NAME; $3='$list_of_swports'"
}
#fi # end of if [[ ! ${NETWORK_COMMONLIB_DIR+x} ]]

#
# Enable switch port connected to the interface on linux server
#
# @parameters
# INPUT
#   $iface is the interface name in linux, like eth0
#
# Example
# swcfg_port_up_by_linux_iface eth0
#
swcfg_port_up_by_linux_iface()
{
	local iface=$1

	echo "$FUNCNAME" "$@"

	local swname=""
	local swport=""

	get_iface_sw_port "$iface" swname swport
	echo "swcfg port_up \"$swname\" $swport"
	swcfg port_up "$swname" "$swport"
}

#
# Disable switch port connected to interface on linux
#
# @parameters
# INPUT
#   $iface is the interface name in linux, like eth0
#
# Example
# swcfg_port_down_by_linux_iface eth0
#
swcfg_port_down_by_linux_iface()
{
	local iface=$1

	echo "$FUNCNAME" "$@"

	local swname=""
	local swport=""

	get_iface_sw_port "$iface" swname swport
	echo "swcfg port_down \"$swname\" \"$swport\""
	swcfg port_down "$swname" "$swport"
}

#
# setup bonding on switch
#    1. create a bonding channel on the switch
#    2. add the required list of interfaces in $1 to the created bond channel
#    3. enable lacp and set it to the required mode $2
#    4. set it to vlan trunk mode, encapsulation 802.1q, and allow vlan 1 ~ 100
#
# @parameters
# INPUT
#   $1: is the list of interfaces on linux in a bonding channel, like 'eth0 eth1'
#   $2: lacp mode active or passive
#
# Example
# swcfg_setup_bonding_by_linux_ifaces 'eth0 eth1' active
#
swcfg_setup_bonding_by_linux_ifaces()
{
	local ifaces_list="$1"
	local lacp_mode=$2

	echo "$FUNCNAME" "$@"

	local swname=""
	local swport=""

	get_iface_sw_port "$ifaces_list" swname swport
	echo "swcfg setup_port_channel \"$swname\" \"$swport\" \"$lacp_mode\""
	swcfg setup_port_channel "$swname" "$swport" "$lacp_mode"
}

#
# Cleanup bonding settings for the required interface list on switch
#
# @parameters
# INPUT
#   $1 is the list of interfaces on linux in a bonding channel, like 'eth0 eth1'
#
# Example
# swcfg_cleanup_bonding_by_linux_ifaces 'eth0 eth1'
#
swcfg_cleanup_bonding_by_linux_ifaces()
{
	local ifaces_list="$1"

	echo "$FUNCNAME" "$@"

	local swname=""
	local swport=""

	get_iface_sw_port "$ifaces_list" swname swport
	echo "swcfg cleanup_port_channel \"$swname\" \"$swport\""
	swcfg cleanup_port_channel "$swname" "$swport"
}

