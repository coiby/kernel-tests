#!/bin/sh

# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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
#  Author: Xiaowu Wu <xiawu@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# In fence kdump it will create 2 cluster nodes. And config and trigger fence kdump in node one.
# Basically two cluster nodes are equal. There is no client/master.


if [ "${RELEASE}" -lt 7 ]; then
    Skip "Fence kdump test is only applicable to RHEL7 or later releases"
    Report
fi

USE_ALIAS=${USE_ALIAS:-"false"}
READ_FROM_PCS=${READ_FROM_PCS:-"true"}

CheckUnexpectedReboot

TestPrepare() {
    local node_type=$1

    # Preparing cluster node2
    InstallPackages pcs pacemaker fence-agents-kdump
    id hacluster
    echo -e "redhat\nredhat" | passwd --stdin hacluster
    systemctl start pcsd.service || {
        MajorError "Failed to start pcsd service."
    }
    systemctl enable pcsd.service
    systemctl enable pacemaker
    systemctl enable corosync

    if [ "${node_type,,}" = "server" ]; then
        server_ip=$(ip ad show | grep 'inet ' | grep global | awk -F' ' '{print $2}' | awk -F'/' '{print $1}')
        client_ip=$(getent ahosts "${CLIENTS}" | grep -v : | head -n 1 | awk '{print $1}')
    else
        client_ip=$(ip ad show | grep 'inet ' | grep global | awk -F' ' '{print $2}' | awk -F'/' '{print $1}')
        server_ip=$(getent ahosts "${SERVERS}" | grep -v : | head -n 1 | awk '{print $1}')
    fi

    if $USE_ALIAS; then
        echo "${client_ip} ${CLIENTS} node1" >> /etc/hosts
        echo "${server_ip} ${SERVERS} node2" >> /etc/hosts
    else
        echo "${client_ip} ${CLIENTS}" >> /etc/hosts
        echo "${server_ip} ${SERVERS}" >> /etc/hosts
    fi

    cat /etc/hosts
}


if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
    Log "- Config cluster node"
    TEST="${TEST}/client"

    TestPrepare client

    # Authorize the nodes and create cluster including node1 and node2.
    Log "- Blocked till the server is ready."
    rstrnt-sync-block -s "DONE" "${SERVERS}" --timeout 3600

    node_list="${CLIENTS} ${SERVERS}"
    if $USE_ALIAS; then
        node_list="node1 node2"
    fi

    # pcs command diffs on RHEL8 and RHEL7
    if $IS_RHEL7; then
        pcs_command="pcs cluster auth ${node_list}"
    else
        pcs_command="pcs host auth ${node_list}"
    fi

    rpm -q --quiet expect || InstallPackages expect
    expect -c '
        set timeout 600
        spawn '"${pcs_command}"'
        expect "Username:"
        send "hacluster\n"
        expect "Password:"
        send "redhat\n"
        expect eof
    '
    if $IS_RHEL7; then
        pcs cluster setup --start --name mycluster ${node_list}
    else
        pcs cluster setup --start mycluster ${node_list}
    fi

    # Sleep for 10s and wait for the cluster to start
    sleep 10

    pcs cluster status || {
        Error "Failed to start pcs cluster"
        Log "- Client finished."
        rstrnt-sync-set -s "DONE"
        report
    }

    # Create pcs stonith resources
    pcs stonith create kdump fence_kdump pcmk_reboot_action="off"
    if $USE_ALIAS; then
        pcs stonith level add 1 node1 kdump
        pcs stonith level add 1 node2 kdump
    else
        pcs stonith level add 1 ${CLIENTS} kdump
        pcs stonith level add 1 ${SERVERS} kdump
    fi

    sleep 20
    pcs cluster cib

    # Configure Kdump
    # if READ_FROM_PCS = 'true' (by default), Kdump would read fence_kdump_nodes from pacemake clustesr configuration.
    # if READ_FROM_PCS = 'false', fence_kdump_nodes will be set explicitly in kdump.config

    if [ "${READ_FROM_PCS,,}" = "false" ]; then
        sed -i /^fence_kdump_nodes /d "${KDUMP_CONFIG}"
        if $USE_ALIAS ; then
            echo "fence_kdump_nodes node2" >> "${KDUMP_CONFIG}"
        else
            echo "fence_kdump_nodes ${SERVERS}" >> "${KDUMP_CONFIG}"
        fi
        sync; sync; sync;
    fi

    RhtsSubmit "${KDUMP_CONFIG}"
    RestartKdump

    pcs config
    pcs cluster cib

    if $IS_RHEL7; then
      lsinitrd ${INITRD_KDUMP_IMG_PATH} | egrep -e "hosts|nsswitch"
    fi

    Log "- Client finished."
    rstrnt-sync-set -s "DONE"

elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
    Log "- Config cluster node"
    TEST="${TEST}/server"

    TestPrepare server

    Log "- Server finished."
    rstrnt-sync-set -s "DONE"

    rstrnt-sync-block -s "DONE" "${CLIENTS}" --timeout 3600

else
    Error "Neither server nor client"
fi

Report
