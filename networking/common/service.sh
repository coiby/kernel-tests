#!/bin/bash
# shellcheck disable=SC2154
# This is basic include file

lib_service()
{
	local service=$1
	local action=$2
	if [ "$(GetDistroRelease)" -ge 7 ];then
		systemctl $action ${service}.service
	else
		service $service $action
	fi
}

# TODO: save iptales on RHEL7, then iptables -F
disable_firewall()
{
	if [ "$(GetDistroRelease)" -ge 7 ];then
		systemctl stop firewalld.service
		systemctl disable firewalld.service
	else
		service iptables save
		service ip6tables save
		service iptables stop
		service ip6tables stop
		chkconfig iptables off
		chkconfig ip6tables off
	fi
}

enable_firewall()
{
	if [ "$(GetDistroRelease)" -ge 7 ];then
		systemctl start firewalld.service
		systemctl enable firewalld.service
	else
		service iptables start
		service ip6tables start
		chkconfig iptables on
		chkconfig ip6tables on
	fi
}

disable_avc_check()
{
	setenforce 0
	[ "$AVC_ERROR" ] && export AVC_ERROR_BAK=$AVC_ERROR
	export AVC_ERROR=+no_avc_check
	export RHTS_OPTION_STRONGER_AVC=
	unset AVC_ERROR_FILE
	[ "$TEST_ID" ] && cp -f /var/log/audit/audit.log /var/log/audit/audit.${TESTID}.bak || :
}

enable_avc_check()
{
	setenforce 1
	{ [ "$AVC_ERROR_BAK" ] && export AVC_ERROR=$AVC_ERROR_BAK; } || \
		{ export AVC_ERROR=`mktemp /mnt/testarea/tmp.XXXXXX` && touch $AVC_ERROR; }
	export RHTS_OPTION_STRONGER_AVC=yes
	export AVC_ERROR_FILE="$AVC_ERROR"
	[ -f /var/log/audit/audit.${TESTID}.bak ] && \
		mv -f /var/log/audit/audit.${TESTID}.bak /var/log/audit/audit.log || return 0
}

stop_NetworkManager()
{
	# If stop NM, RHEL7 cannnot respawn dhclient for beaker interface,
	# and result in lost management IP address after DHCP expired.
	# Let's keep NetworkManger running and just set non-beaker interfaces NM_CONTROLLED=no

	local beaker_nic=$(get_default_iface)
	echo DEBUG::: beaker_nic=$beaker_nic
	rhel_verx=$(GetDistroRelease)
	if [ $rhel_verx -ge 9 ];then
		OLD_IFS=$IFS
		IFS=$'\n'
		for uuid in $(nmcli -f UUID con show | tail -n +2 | sed 's/[ ]*$//g');do
			ifname=$(nmcli -g connection.interface-name con show $uuid)
			[ "$ifname" == "$beaker_nic" ] && continue
			[ "$ifname" == "loopback" ] && continue
			[ "$ifname" == "lo" ] && continue
			[ "$ifname" == "virbr0" ] && continue
			echo "deleting NM connection:$uuid with device:$ifname"
			nmcli con del "$uuid"
		done

		for d in $(nmcli -f DEVICE device status|tail -n +2|sed 's/[ ]*$//g');do
			[ "$d" == "$beaker_nic" ] && continue
			[ "$d" == "loopback" ] && continue
			[ "$d" == "lo" ] && continue
			[ "$d" == "virbr0" ] && continue
			nmcli dev set $d managed no
			for config in "accept_ra" "accept_ra_defrtr" "accept_ra_pinfo" "accept_ra_rtr_pref"
				do
					echo 1 > /proc/sys/net/ipv6/conf/$d/$config
			done
			ip link set $d down
		done
		IFS=$OLD_IFS
	else
		#interface will configure ip address in RHEL8.3, which affects testing, here down all the connections
		#except "System ***" to elimate ip address configured.
		# The connection name(with default interface) doesn't contain the
		# string 'System' on some aarch64 systems, so use $beaker_nic as the filter pattern
		connection_list=`nmcli connection | grep -v -E "${beaker_nic}|virbr0" | awk 'NR==1 {next} {print $(NF-2)}'`
		device_list=`nmcli device status | awk 'NR==1 {next} {print $1}' | grep -v -E "${beaker_nic}|virbr0"`
		for interface in $connection_list; do
			nmcli connection down $interface
		done
		unset connection_list

		# port name maybe changed after upgrading kernel(sometimes this is because of bug, sometimes this is by design),
		# but the cfg file name in /etc/sysconfig/network-scripts/ maybe not changed accordingly(still use the old file name),
		# so we also need to search devices in output of "nmcil con show" instead of only search it in /etc/sysconfig/network-scripts/ directory,
		# because some devices maybe not included in /etc/sysconfig/network-scripts/ because of the above reason
		for devname in $device_list; do
			if [ -e /etc/sysconfig/network-scripts/ifcfg-$devname ];then
				f=/etc/sysconfig/network-scripts/ifcfg-$devname
				sed -i 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' $f
				if grep -q NM_CONTROLLED $f; then
					sed -i 's/NM_CONTROLLED=yes/NM_CONTROLLED=no/g' $f
				else
					sed -i '$a\NM_CONTROLLED=no' $f
				fi
			fi
			nmcli dev set $devname managed no
			#In RHEL-7.3-beta, NetworkManager would set accept_ra of nic to 0,so restore
			#them to 1.As the nic controlled by NetworkManager has no local ipv6 addr,so
			#down these cards,up them when need to use and local ipv6 addr would be generated
			#corresponsively
			for config in "accept_ra" "accept_ra_defrtr" "accept_ra_pinfo" "accept_ra_rtr_pref"
				do
					echo 1 > /proc/sys/net/ipv6/conf/$devname/$config
			done
			ip link set $devname down
		done

		for f in /etc/sysconfig/network-scripts/ifcfg-*; do
			grep -q $beaker_nic $f && continue
			grep -q loopback $f && continue

			sed -i 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' $f
			if grep -q NM_CONTROLLED $f; then
				sed -i 's/NM_CONTROLLED=yes/NM_CONTROLLED=no/g' $f
			else
				sed -i '$a\NM_CONTROLLED=no' $f
			fi
			#In RHEL-7.3-beta, NetworkManager would set accept_ra of nic to 0,so restore
			#them to 1.As the nic controlled by NetworkManager has no local ipv6 addr,so
			#down these cards,up them when need to use and local ipv6 addr would be generated
			#corresponsively
			devname=`basename $f | cut -f 2 -d -`
			nmcli dev set $devname managed no
			for config in "accept_ra" "accept_ra_defrtr" "accept_ra_pinfo" "accept_ra_rtr_pref"
			do
				echo 1 > /proc/sys/net/ipv6/conf/$devname/$config
			done
			ip link set $devname down
		done
	fi
	systemctl stop NetworkManager
	systemctl start NetworkManager

	if [ "$(GetDistroRelease)" -le 8 ];then
		[ -d $networkLib/network-scripts.no_nm/ ] || \
			rsync -a --delete /etc/sysconfig/network-scripts/ $networkLib/network-scripts.no_nm/
	else
		[ -d $networkLib/system-connections.no_nm ] || \
			rsync -a --delete /etc/NetworkManager/system-connections/ $networkLib/system-connections.no_nm/
	fi

	lib_service NetworkManager status &> /dev/null || return 0
	lib_service NetworkManager restart

	nmcli con show
	nmcli device status
	ip addr show
}

# Config Networkmanager to ignore network interfaces except beaker port.
# This configuration could valid even after reloading driver.
set_nm_unmanage()
{
	rhel_ver=$(GetDistroRelease)
	[ $rhel_ver -lt 7 ] && return

	default_iface=$(get_default_iface)

	# delete old cfg first
	#sed -i '/\[keyfile\]/d' /etc/NetworkManager/NetworkManager.conf
	#sed -i '/unmanaged-devices/d' /etc/NetworkManager/NetworkManager.conf

	# ignore ports except beaker port
	echo "[keyfile]" >> /etc/NetworkManager/NetworkManager.conf
	echo "unmanaged-devices=except:interface-name:$default_iface" \
		>> /etc/NetworkManager/NetworkManager.conf

	systemctl restart NetworkManager
}

# You'd better restore the configuration at the end of your case.
unset_nm_unmanage()
{
	rhel_ver=$(GetDistroRelease)
	[ $rhel_ver -lt 7 ] && return

	sed -i '/\[keyfile\]/d' /etc/NetworkManager/NetworkManager.conf
	sed -i '/unmanaged-devices/d' /etc/NetworkManager/NetworkManager.conf

	systemctl restart NetworkManager

	# need to call stop_NetworkManager when NM_CTL==no
	if [ "$NM_CTL" == "no" ];then
		stop_NetworkManager &>/dev/null
	fi
}
