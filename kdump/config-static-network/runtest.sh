#!/bin/sh

# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
. ../include/runtest.sh

CheckUnexpectedReboot

NETDEV=${TESTNICS:-""}

ConfigStaticNetwork() {

    if [ -z "$TESTNICS" ]; then
        TESTNICS=$(ip route | awk '$1=="default" {print $5}')
    fi

    if [ -z "$TESTNICS" ]; then
        MajorError "No net device to configure"
    fi

    ifcfgdir="/etc/sysconfig/network-scripts"

    touch ${K_NET_IFCFG}

    for NIC in $TESTNICS; do
        Log "Start to configure $NIC"

        LogRun "ip add show"

        unset _mac _ifcfg _ipaddr _prefix _netmask _broadcast _gateway

        if ip addr show dev $NIC | awk '$1=="inet"' | grep -qv dynamic; then
            Log "$NIC has already configured as static network, skipped"
            continue
        fi

        _mac=$(ip link show dev $NIC | awk '$1=="link/ether" {print $2}')
        if [ -z "$_mac" ]; then
            FatalError "$NIC doesn't exist"
        fi

        # Pick up the right ifcfg-NIC file, then back up.
        # Rename it if need, since sometimes ifcfg-eth0 turns out to handle eth1.

        _ifcfg=$ifcfgdir/ifcfg-$NIC

        if [ -f "$_ifcfg" ]; then
            [ ! -f "${_ifcfg}.bk" ] && cp $_ifcfg ${_ifcfg}.bk
            RhtsSubmit ${_ifcfg}.bk
        fi

        # Get static configuration from environment
        _ipaddr=$(ip addr show dev $NIC |
            awk '$1=="inet" {print substr($2, 1, index($2, "/") - 1)}')
        _prefix=$(ip addr show dev $NIC |
            awk '$1=="inet" {print substr($2, index($2, "/") + 1)}')
        # _netmask=$(ipcalc -m $_ipaddr/$_prefix | cut -d= -f2)
        # _broadcast=$(ipcalc -b $_ipaddr/$_prefix | cut -d= -f2)
        _gateway=$(ip route show dev $NIC | awk '$1=="default" {print $3}')
        _dns1=$(awk '/^nameserver .*/ {if (++c==1) print $2}' /etc/resolv.conf)
        _dns2=$(awk '/^nameserver .*/ {if (++c==2) print $2}' /etc/resolv.conf)

        if [ ! -f $_ifcfg ]; then

            {
                echo "[keyfile]"
                echo "unmanaged-devices=none"
            } | tee /etc/NetworkManager/conf.d/10-globally-managed-devices.conf

            # ip addr del $_ipaddr/$_prefix dev $NIC
            # ip addr add $_ipaddr/$_prefix dev $NIC
            # ip route add default via $_gateway dev $NIC

            con_name=$(nmcli d show $NIC | grep GENERAL.CONNECTION | awk '{print $2}')

            # back up old configuration
            [ -f "${K_NMCLI_PATH}/${con_name}.nmconnection.bk" ] ||
                cp -f "${K_NMCLI_PATH}/${con_name}.nmconnection" "${K_NMCLI_PATH}/${con_name}.nmconnection.bk"

            nmcli connection modify $con_name ipv4.addresses $_ipaddr/$_prefix
            nmcli connection modify $con_name ipv4.method manual
            nmcli connection modify $con_name ipv4.gateway $_gateway
            nmcli connection modify $con_name ipv4.dns $_dns1
            nmcli connection up $con_name

            RhtsSubmit "${K_NMCLI_PATH}/${con_name}.nmconnection"
            RhtsSubmit "${K_NMCLI_PATH}/${con_name}.nmconnection.bk"
        else

            # Configure ifcfg-NIC
            {
                echo "IPADDR=$_ipaddr"
                echo "PREFIX=$_prefix"
                # echo "NETMASK=$_netmask"
                # echo "BROADCAST=$_broadcast"
                echo "GATEWAY=$_gateway"
                echo "DNS1=$_dns1"
                echo "DNS2=$_dns2"
            } | tee -a $_ifcfg
            sed -i -e "s/\(DEVICE\)=.*/\1=$NIC/" \
                -e "s/\(HWADDR\)=.*/\1=$_mac/" \
                -e "s/\(ONBOOT\)=.*/\1=yes/" \
                -e "s/\(BOOTPROTO\)=.*/\1=static/" $_ifcfg

            RhtsSubmit $_ifcfg

            # Restart Network
            nmcli connection reload
            nmcli device reapply $NIC

        fi

        ping -I $NIC -c 3 8.8.8.8 || {
            Log "Fail to restart network"
            Log "Try to restore network"
            for f in ./ifcfg-*-bak; do
                mv $f $ifcfgdir/${f%%-bak}
            done

            nmcli connection reload
            nmcli device reapply $NIC

            FatalError "Fail to configure $1 to static"
        }
        Log "Done configuring $NIC"
        LogRun "ip add show"

        Report "Config $NIC"
    done

}

ServerClientCheck() {

    if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
        Log "Run as client"
        TEST="${TEST}/client"

        # Abort entire recipeset if not reciving Done signal from server
        Log "[sync] Blocked till the server side is ready."
        rstrnt-sync-block -s "READY" "${SERVERS}" --timeout 3600 || FatalError "[sync] Not receiving READY signal from server"

        ConfigStaticNetwork

        Log "[sync] Client finished"
        rstrnt-sync-set -s "DONE"

    elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
        Log "Run as server"
        TEST="${TEST}/server"

        Log "[sync] Server is ready"
        rstrnt-sync-set -s "READY"

        # Abort only current task if not receving Done signal from client
        Log "[sync] Blocked till the client side is done."
        rstrnt-sync-block -s "DONE" "${CLIENTS}" --timeout 3600 || MajorError "[sync] Not receiving DONE signal from client"
    else
        Log "Run as single host client"
        ConfigStaticNetwork
    fi

}

# --- start ---
ServerClientCheck
Report
