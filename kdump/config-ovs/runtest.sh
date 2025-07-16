#!/bin/bash
#
# Source Kdump tests common functions.
# shellcheck disable=SC1091
. ../include/runtest.sh

BOND_NIC=bond0
OVS_CONFIGURE_SCRIPT=/usr/local/bin/configure-ovs.sh

add_ovs_repo() {
	cat <<EOF >/etc/yum.repos.d/ovs.repo
[OVS]
name=OVS
baseurl=https://buildlogs.centos.org/centos/\$releasever-stream/nfv/\$basearch/openvswitch-2/
gpgcheck=0
EOF
}

install_ovs_package() {
	if ! grep -qs Fedora /etc/redhat-release; then
		add_ovs_repo
	fi
	# RHEL/CentOS may use package name like openvswitch3.5 whereas Fedora uses
	# openvswitch. So use /usr/bin/ovs-vsctl to let dnf automatically find the
	# needed package.
	dnf install /usr/bin/ovs-vsctl -y
}

extract_configure_ovs_script() {
	local _script_url

	_script_url=https://raw.githubusercontent.com/openshift/machine-config-operator/refs/heads/main/templates/common/_base/files/configure-ovs-network.yaml

	if curl -sL $_script_url | grep -A4000 '#!/bin/bash' >"$OVS_CONFIGURE_SCRIPT"; then
		chmod +x "$OVS_CONFIGURE_SCRIPT"
	else
		Warn +x "Failed to exract configure-ovs.sh from $_script_url. Use old backup"
		cp configure-ovs.sh "$OVS_CONFIGURE_SCRIPT"
	fi
}

create_bond_network() {
	local _ifname

	_ifname=$(ip route show default | awk '{print $5}') || return 1
	nmcli con add type bond ifname "$BOND_NIC"
	nmcli con add type ethernet ifname "$_ifname" master "$BOND_NIC"
	nmcli con up "bond-slave-$_ifname"
}

setup_ovs() {
	create_bond_network

	mkdir -p /etc/ovnk
	echo "$BOND_NIC" >/etc/ovnk/iface_default_hint

	"$OVS_CONFIGURE_SCRIPT" OVNKubernetes

	if ! ovs-vsctl iface-to-br "$BOND_NIC"; then
		MajorError "Failed to set up OVS bridge network"
		return 1
	fi

	# make the connections persistent
	if [[ $OVS_CONNECTION_PERSISTENT == yes ]]; then
		cp /run/NetworkManager/system-connections/* /etc/NetworkManager/system-connections/
	fi
}

if [ "$RELEASE" -eq 10 ]; then
	CheckSkipTest kdump-utils 1.0.54 && return
fi

install_ovs_package
systemctl enable --now openvswitch
# restart NM so the ovs plugin can be activated
systemctl restart NetworkManager
extract_configure_ovs_script
setup_ovs
Report
