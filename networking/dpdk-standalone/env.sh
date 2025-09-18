#!/bin/bash
# shellcheck disable=SC2034

#SYSTEM_CONFIG
################################################################
#SYSTEM_VERSION=${SYSTEM_VERSION:-"RHEL-8.0-20181029.3"}
# VM image OVS DPDK BONDING TEST
IMG_GUEST=http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/vm/rhel9.2-vsperf-1Q-viommu.qcow2
################################################################

#PLEASE KEEP THE FOLLOW SECTION CONFIG FIXED
#BOND_TEST_MODE_IPERF CONFIG
##################################################################
SERVER_VCPUS=${SERVER_VCPUS:-2}
CLIENT_VCPUS=${CLIENT_VCPUS:-2}
CLIENT_GUEST_IP=${CLIENT_GUEST_IP:-192.168.99.200}
SERVER_GUEST_IP=${SERVER_GUEST_IP:-192.168.99.201}
# hostname for the machines
# The name must be the same as shown by linux command hostname
# and the names for CLIENTS and SERVERS must not be the same
SERVERS=${SERVERS}
CLIENTS=${CLIENTS}
##################################################################

#NOTICE PLEASE FIX YOUR CONFIG FROM HERE BELOW
#CONN_TYPE netscout only or null
CONN_TYPE=
NETSCOUT_HOST=${NETSCOUT_HOST}
#traffic_type ,can  be xena trex
TRAFFIC_TYPE=${TRAFFIC_TYPE:-xena}
################################################################################
#TRAFFIC TREX CONFIG
#ONLY ENABLED WITH TRAFFIC_TYPE==trex
#the host ip that  started the t-rex-64 -i with this host
TREX_SERVER_IP=${CLIENTS}
TREX_SERVER_PASSWORD=${TREX_SERVER_PASSWORD}
TREX_URL=http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/tools/v2.87.tar.gz

#TOPO PORT NAME
#NOTE: IF Your environment is NOT connect with netscout , do not fill the following item
#THE FOLLOWING SECTION ITME ONLY ENABLED WITH NETSCOUT
SERVER_PORT_ONE=${SERVER_PORT_ONE}
SERVER_PORT_TWO=${SERVER_PORT_TWO}
CLIENT_PORT_ONE=${CLIENT_PORT_ONE}
CLIENT_PORT_TWO=${CLIENT_PORT_TWO}

########################################################################################
#CLIENT AND SERVER HOST NIC CONFIG
NIC_DRIVER=${NIC_DRIVER:-ice}
if [ "$SERVERS" == "netqe35.knqe.eng.rdu2.dc.redhat.com" ]; then
    SERVER_NIC1_MAC='50:7c:6f:62:35:ba'
    SERVER_NIC2_MAC='50:7c:6f:62:35:bb'
    CLIENT_NIC1_MAC='50:7c:6f:62:35:a6'
    CLIENT_NIC2_MAC='50:7c:6f:62:35:a7'
elif [ "$SERVERS" == "netqe36.knqe.eng.rdu2.dc.redhat.com" ]; then
    CLIENT_NIC1_MAC='50:7c:6f:62:35:ba'
    CLIENT_NIC2_MAC='50:7c:6f:62:35:bb'
    SERVER_NIC1_MAC='50:7c:6f:62:35:a6'
    SERVER_NIC2_MAC='50:7c:6f:62:35:a7'
elif [ "$SERVERS" == "hpe-netqe-syn480g10-06.knqe.eng.rdu2.dc.redhat.com" ]; then
    CLIENT_NIC1_MAC='20:67:7c:13:e0:06'
    CLIENT_NIC2_MAC='20:67:7c:13:e0:07'
    SERVER_NIC1_MAC='b8:83:03:62:e0:34'
    SERVER_NIC2_MAC='b8:83:03:62:e0:35'
elif [ "$SERVERS" == "hpe-netqe-syn480g10-08.knqe.eng.rdu2.dc.redhat.com" ]; then
    CLIENT_NIC1_MAC='b8:83:03:62:e0:34'
    CLIENT_NIC2_MAC='b8:83:03:62:e0:35'
    SERVER_NIC1_MAC='20:67:7c:13:e0:06'
    SERVER_NIC2_MAC='20:67:7c:13:e0:07'
else
    echo "unknown machine"
fi

#OPENVSWITCH AND DPDK CONFIG
#DPDK_TEST_OPTION select which dpdk type will be tested {rpm|source}
#The default option is rpm
DPDK_TEST_OPTION=${DPDK_TEST_OPTION:-"rpm"}
DPDK_URL=http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/tools/dpdk-23.11-1.el9.x86_64.rpm
DPDK_TOOL_URL=http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/tools/dpdk-tools-23.11-1.el9.x86_64.rpm
DRIVERCTL_URL=http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/tools/driverctl-0.111-2.el9.noarch.rpm
DPDK_SOURCE=${DPDK_SOURCE:-"http://fast.dpdk.org/rel/dpdk-23.11.tar.xz"}
DPDK_VERSION=23.11-1.el9
export DPDK_VERSION=$DPDK_VERSION
GUEST_DPDK_VERSION=23.11-1.el9
GUEST_DPDK_URL=${DPDK_URL}
GUEST_DPDK_TOOL_URL=${DPDK_TOOL_URL}
TEST_ITEM_LIST="cki"

NAY=yes
#CONFIG END , DO NOT EDIT THE FOLLOW CODE UNLESS YOU SURE YOU CAN !!!
##################################################################################################
##################################################################################################
TEST_ITEM_LIST=${TEST_ITEM_LIST:-"all"}
# current supported item list
# dpdk_bind_and_unbind_test
# dpdk_port_info_test
# dpdk_port_blocklist_test
# dpdk_testpmd_in_container_test
# dpdk_sriov_vf_bug2088787_test
# dpdk_port_state_change_test
# dpdk_mtu_and_jumbo_packet_test
# dpdk_checksum_offload_test
# dpdk_tso_test
# dpdk_gso_and_gro_test
# dpdk_rss_test
# dpdk_broadcast_test
# dpdk_multicast_test
# dpdk_promisc_test
# dpdk_vlan_test
# dpdk_qinq_test
# dpdk_tunnel_vxlan_test
# dpdk_tunnel_gre_test
# dpdk_virtio_user_as_exceptional_path_ipv4_test
# dpdk_virtio_user_as_exceptional_path_ipv6_test
# dpdk_l3_forwarding_test
# dpdk_sriov_vf_vlan_for_bug_2131310_test
# dpdk_sriov_vf_multiple_queues_test
# dpdk_sriov_vf_func_test
# dpdk_sriov_single_vf_test
# dpdk_sriov_vf_vlan_without_vlan_filter_test
# dpdk_sriov_vf_vlan_test
# dpdk_sriov_vf_mtu_test
# dpdk_sriov_vf_mtu_test
# dpdk_sriov_vf_mtu_test
# dpdk_sriov_vf_mtu_test
# dpdk_sriov_vf_broadcast_test
# dpdk_sriov_vf_multicast_test
# dpdk_sriov_vf_promisc_test
# dpdk_sriov_vf_promisc_bug2101710_test
# dpdK_sriov_vf_in_guest_test
# dpdK_sriov_vf_in_guest_bug2143985_test
# dpdk_flow_bifurcation_test
# dpdk_testpmd_l2_performance_test
# dpdk_sriov_testpmd_in_guest_performance_test
# dpdk_sriov_vf_config_vsi_queues_bug2137378_test
# dpdk_sriov_vf_bug2091552_test
##################################################################################################
##################################################################################################
function advanced_qemu_install()
{
    rhel_version=$(cut -f1 -d. /etc/redhat-release | sed 's/[^0-9]//g')
    if [[ $rhel_version -ne 8 ]]; then
        echo "System must be running RHEL-8"
        return 0
    fi

    if [[ $(hostname | grep "bos") ]]; then
        location=bos
    else
        location=pek2
    fi

    . /etc/os-release
    # if [[ $VERSION_ID == "8.1" ]] || [[ $VERSION_ID == "8.2" ]]; then
    #     VERSION_ID="8.1"
    # fi

    pushd /tmp
    rm -f index.html
    if [[ ! $(wget -V) ]]; then yum -y install wget; fi
    wget -q --execute="robots = off" --convert-links --no-parent --wait=1 http://download.devel.redhat.com/rhel-8/rel-eng/ADVANCED-VIRT-8/
    partial_custom_qemu_url=$(grep latest-ADVANCED index.html | grep latest-ADVANCED-VIRT-$VERSION_ID | awk '{print $5}' | awk -F "=" '{print $2}' | awk -F '"' '{print $2}' | tail -1)
    custom_qemu_url="$partial_custom_qemu_url"compose/Advanced-virt/x86_64/os

    cat >/etc/yum.repos.d/qemu.repo <<-EOF
[qemu]
name=qemu
baseurl=${custom_qemu_url}
enabled=1
gpgcheck=0
skip_if_unavailable=1
EOF

    dnf -y remove @virt
    dnf -y module reset virt
    virt_stream=$(dnf module list | grep virt | tail -n1 | awk '{print $2}')
    dnf -y module enable virt:$virt_stream/common
    dnf -y install libpmem
    dnf -y install qemu-kvm
    dnf -y install qemu-img
    dnf -y install --repo qemu qemu-kvm
    dnf -y install libvirt
    sleep 3

    rpm -qa | grep qemu
    rm -f index.html
    popd
}
