#!/bin/bash

# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Author: Xiaowu Wu <xiawu@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

NETWORK_CONFIG=${NETWORK_CONFIG:-"/etc/sysconfig/network-scripts/"}

ConfigNetwork()
{
    local br=br0

    if [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then
        rpm -q --quiet bridge-utils || InstallPackages bridge-utils
        if $IS_RHEL8 ; then
            InstallPackages network-scripts
        fi
        local eth="$(ip route | grep default | awk '{print $5}')"

        LogRun "ip a show"
        Log "Pick up iface ${eth}, bridge ${br}"

        if [ "${RELEASE}" -gt 8 ]; then
            Log "Configuring bridged network by nmcli"

            # nmcli connection add type bridge ifname $br stp no
            # nmcli connection add type bridge-slave ifname $eth master $br
            # nmcli connection up bridge-slave-$eth
            LogRun "ip route; ip address; nmcli con show"
            LogRun "nmcli connection add type bridge ifname $br stp no"
            LogRun "nmcli connection add type bridge-slave ifname $eth master $br"
            LogRun "nmcli connection up bridge-slave-$eth"
            LogRun "nmcli connection modify $eth autoconnect no"
            LogRun "sleep 5; sync; sync; sync"
            LogRun "ip route; ip address; nmcli con show"
        else

            Log "Configuring bridged network by ifcfg files"
            local eth_config="${NETWORK_CONFIG}/ifcfg-${eth}"
            local br_config="${NETWORK_CONFIG}/ifcfg-${br}"

            cat <<EOF > "${br_config}"
DEVICE=${br}
TYPE=Bridge
BOOTPROTO=dhcp
ONBOOT=yes
EOF
            Log "Generated ${br_config}"
            if [ -f "${eth_config}" ]; then
                local net_type=$(grep "NETTYPE=" "${eth_config}")
                local sub_channel=$(grep "SUBCHANNEL" "${eth_config}")
                local opts=$(grep "OPTIONS=" "${eth_config}")
                local macaddr=$(grep "ACADDR=" "${eth_config}")

                cp "${eth_config}" "${eth_config}".origin
                RhtsSubmit "${eth_config}".origin
                rm "${eth_config}".origin
            fi

            cat <<EOF > "${eth_config}"
DEVICE=${eth}
TYPE=Ethernet
ONBOOT=yes
BRIDGE=br0
EOF
            [ -n "${net_type}" ] && echo "${net_type}" >> "${eth_config}"
            [ -n "${sub_channel}" ] && echo "${sub_channel}" >> "${eth_config}"
            [ -n "${opts}" ] && echo "${opts}" >> "${eth_config}"
            [ -n "${macaddr}" ] && echo "${macaddr}" >> "${eth_config}"
            Log "Generated ${eth_config}"

            RhtsSubmit "${br_config}"
            RhtsSubmit "${eth_config}"
            sync;sync;sync
        fi

        Log "Reboot system"
        RhtsReboot
        # Log "Restarting network"
        # if which systemctl > /dev/null 2>&1 ; then
        #     LogRun "ip ad flush ${eth}; systemctl restart NetworkManager 2>&1"
        # else
        #     LogRun "ip ad flush ${eth}; service network restart 2>&1"
        # fi
        # [ $? -eq 0 ] || MajorError "Failed to restart network!"

        # sleep 60
    elif [ "${RSTRNT_REBOOTCOUNT}" -eq 1 ]; then

        Log "Checking bridge status"
        LogRun "ip a show"
        if $IS_RHEL9 || $IS_FC ; then
            local brif="$(nmcli c show|grep bridge-slave|awk '{print $1}')"
            LogRun "nmcli con up $brif; nmcli con show"
        fi

        which ifconfig > /dev/null 2>&1 && LogRun "ifconfig"
        ip a show dev "$br" | grep 'inet ' | grep -q global || {
            FatalError "Failed to setup $br."
        }

        # RestartKdump could fail on 'ibm-z-5xx*' machines due to known
        # issue, bz2064708:
        #  kdump fails to build initrd for network  for bridge network on z15 z/vm,
        #   dracut: Failed to set up znet
        #   kdump: mkdumprd: failed to make kdump initrd
        RestartKdump
    else
        MajorError "Unexpected reboot is detected. Please check if system has \
been rebooted from panic or other possible incidents."
    fi
}

Multihost "ConfigNetwork"

