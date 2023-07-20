#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/networking/vnic/sriov
#   Author: Qijun Ding <qding@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# test

# variables
PACKAGE="kernel"
dbg_flag=${dbg_flag:-"set +x"}
$dbg_flag
SYNC_TIME=${SYNC_TIME:-"14000"}
NAY=${NAY:-yes}
NIC_DRIVER=${NIC_DRIVER:-any}
NIC_NUM=${NIC_NUM:-1}
DPDK_URL=${DPDK_URL:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/17.11/11.el7/x86_64/dpdk-17.11-11.el7.x86_64.rpm"}
DPDK_TOOLS_URL=${DPDK_TOOLS_URL:-"http://download-node-02.eng.bos.redhat.com/brewroot/packages/dpdk/17.11/11.el7/x86_64/dpdk-tools-17.11-11.el7.x86_64.rpm"}
CASE_PATH=$(dirname $(readlink -f $BASH_SOURCE))
# Include Beaker environment
source ${CASE_PATH}/../../common/include.sh || exit 1

source ${CASE_PATH}/env.sh

# source rt kernel tuning script
source ${CASE_PATH}/rt-kernel/set_up.sh

source ${CASE_PATH}/../../common/lib/lib_nc_sync.sh || exit 1
#source ${CASE_PATH}/../../common/lib/lib_swcfg.sh || exit 1
source ../../common/lib/lib_swcfg.sh || exit 1
#. ${CASE_PATH}/../../common/lib/lib_netperf_all.sh || exit 1
. ./lib_netperf_all.sh || exit 1
. ${CASE_PATH}/lib_sriov.sh || exit 1

source ${CASE_PATH}/sriov_bond.sh
source ${CASE_PATH}/regression.sh
# nfp specific setting
if [ "$NIC_DRIVER" == "nfp" ] && echo $SRIOV_TOPO|grep -v switchdev  && i_am_client;then
		nfp_change_firmware
fi
# cxgb4 specific setting
if [ "$NIC_DRIVER" == "cxgb4" ] && i_am_client;then
		SRIOV_USE_HOSTDEV=yes
fi

br_bkr=${br_bkr:-br0}
export vm1=${vm1:-g1}
export vm2=${vm2:-g2}
export vm3=${vm3:-g3}
export container1=${container1:-sriov_c1}
export container2=${container2:-sriov_c2}
export container3=${container3:-sriov_c3}
export container4=${container4:-sriov_c4}
export pod1=${pod1:-sriov_pod1}
export pod2=${pod2:-sriov_pod2}
export c_image=${c_image:-docker.io/library/centos8}
export c_image_arm=${c_image_arm:-localhost/centos_stream_8_aarch64:latest}
export c_image_ppc64le=${c_image_ppc64le:-localhost/centos_stream8:latest}

nic_test=""
ipaddr=""
ipaddr_vlan=""
result_file=""

if  uname -a|grep aarch ;then
	SYS_ARCH=aarch
elif  uname -a|grep ppc64le ;then
	SYS_ARCH=ppc64le
else
	SYS_ARCH=x86
fi

install_pktgen()
{
	$dbg_flag
	local kname1="kernel" && [ -x /usr/sbin/kernel-is-rt ] && kname1="kernel-rt"
	local kname2="${kname1}"
	local kernel_ver="$(uname -r)"
	uname -r|grep "debug" && {
		local kname2="${kname1}-debug"
		kernel_ver="$(uname -r| sed 's/.debug//')"
	}

	modprobe pktgen && { modprobe -r pktgen; return 0; }
		if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
			PKTGEN_URL="http://download-node-02.eng.bos.redhat.com/brewroot/packages/kernel-rt"
			PKTGEN_PACKAGE_NAME="kernel-rt-modules-internal"
		elif [[ $ENABLE_RT_KERNEL == "no" ]]; then
			PKTGEN_URL="http://download.eng.bos.redhat.com/brewroot/packages/kernel"
			PKTGEN_PACKAGE_NAME="kernel-modules-internal"
		fi

		RPM_MODULES_INTERNAL=$(uname -r | awk -v pktgen_url="$PKTGEN_URL" -v pktgen_package_name="$PKTGEN_PACKAGE_NAME" '{
			split($0,v,"-");
			s=v[2];
			do {
					i=index(s,".")
					s=substr(s, i+1)
			}while(i>0)
			sub("."s,"",v[2])
			print pktgen_url"/"v[1]"/"v[2]"/"s"/"pktgen_package_name"-"v[1]"-"v[2]"."s".rpm"
	}')
	rpm -ivh $RPM_MODULES_INTERNAL
	yum install -y  ${kname2}-modules-internal-${kernel_ver}
}

# assign IP address for test
sriov_get_ipaddr()
{
	$dbg_flag
	if [ -z "$JOBID" ]; then
		ipaddr=214
		ipaddr_vlan=213
	else
		ipaddr=$((JOBID % 100 + 20))
		ipaddr_vlan=$(($ipaddr + 50))
	fi
}

# install needed packages
sriov_install()
{
	$dbg_flag
	# use ip link instead of brctl
	#if ! brctl -V 2>/dev/null; then
	#	yum -y install bridge-utils
	#fi

	# netperf
	#if ! netperf -V 2>/dev/null; then
	#	pushd /root/ 1>/dev/null
	#	wget -nv -N $SRC_NETPERF
	#	tar xjvf $(basename $SRC_NETPERF)
	#	cd $(tar -jtf $(basename $SRC_NETPERF) | head -n 1)
	#	./configure && make && make install
	#	popd 1>/dev/null
	#fi
	netperf_install
	#for tests on Fedora, pip is missing somehow, and scapy_install would fail. So add pip installation below
	yum install -y pip
	scapy_install
	pkill netserver; sleep 2; netserver

	yum install -y pciutils vim
	#install podmad for container
	yum -y install podman

	# libvirt && kvm
	yum -y install virt-install
	yum -y install libvirt
	if (($rhel_version >= 8)); then
		yum install -y python3-lxml.x86_64
	fi
	test -f /etc/yum.repos.d/beaker-tasks.repo && mv /etc/yum.repos.d/beaker-tasks.repo /root/beaker-tasks.repo
	rpm -qa | grep qemu-kvm >/dev/null || yum -y install qemu-kvm
	test -f /root/beaker-tasks.repo && mv /root/beaker-tasks.repo /etc/yum.repos.d/beaker-tasks.repo
	if (($rhel_version < 7)); then
		service libvirtd restart
	else
		systemctl restart libvirtd
		systemctl start virtlogd.socket
	fi
	# work around for failure of virt-install
	chmod 666 /dev/kvm

	#workaround for bz1961562
	mkdir -p /etc/qemu/firmware
	touch /etc/qemu/firmware/50-edk2-ovmf-cc.json

}

enable_libvirtd_as_default_rhel9(){
	for drv in qemu interface network nodedev nwfilter secret storage proxy
	do
		rlRun "systemctl unmask virt${drv}d.service"
		rlRun "systemctl unmask virt${drv}d{,-ro,-admin}.socket"
		rlRun "systemctl enable virt${drv}d.service"
		rlRun "systemctl is-enabled virt${drv}d.service"
		rlRun "systemctl enable virt${drv}d{,-ro,-admin}.socket"
		rlRun "systemctl is-enabled virt${drv}d{,-ro,-admin}.socket"
		rlRun "systemctl start virt${drv}d.service"
		rlRun "systemctl status virt${drv}d.service"
	done
	rlRun "systemctl unmask libvirtd.service"
	rlRun "systemctl enable libvirtd.service"
	rlRun "systemctl is-enabled libvirtd.service"
	rlRun "systemctl unmask libvirtd{,-ro,-admin}.socket"
	rlRun "systemctl enable libvirtd{,-ro,-admin}.socket"
	rlRun "systemctl is-enabled libvirtd{,-ro,-admin}.socket"
}

# this will be called before and after the test
sriov_cleanup()
{
	$dbg_flag
	local dev_beaker=$(ip route|grep "^default" | awk '{printf $NF}')
	local mac_beaker=$( ip link show $(
		ip route | grep "^default" | awk '{ printf $NF }') |
		awk --re-interval '{
			match($0,"link/ether (([[:xdigit:]]{2}:){5}[[:xdigit:]]{2})", M);
			printf M[1]
		}'
	)
	if (( $(ip link show | grep -i $mac_beaker | wc -l) > 1 )); then
		local nic_bkr=$(
			ip link show | grep -i $mac_beaker -B 1 |
			awk '{
				if (match($0, "^[[:digit:]]+:[[:blank:]]+(.*):.*", M) && ("ethtool -i "M[1]|getline) && ($0!~/bridge/)) {
					printf M[1]
				}
			}'
		)

		# delete the beaker nic from the bridge
		# and start dhclient on beaker nic
		pkill dhclient
		sleep 5
		#brctl delif $dev_beaker $nic_bkr
		ip link set dev $nic_bkr nomaster
		dhclient $nic_bkr
		ip addr flush dev $dev_beaker
	fi

	# echo "remove any bridge if exist"
	#brctl show | sed -n 2~1p | awk '/^[[:alpha:]]/ { system("ip link set "$1" down; brctl delbr "$1) }'
	ip link show type bridge | sed -n 1~2p | awk -F ":" '{ system("ip link set "$2" down; ip link del "$2) }'

	# echo "remove any VM if exist"
	virsh list --all | sed -n 3~1p |
	awk '/[[:alpha:]]+/ {
		if ($3 == "running") {
			system("virsh shutdown "$2);
			sleep 2;
			system("virsh destroy "$2)
		};
		system("virsh undefine --nvram --managed-save --snapshots-metadata --remove-all-storage "$2)
	}'

	# echo "remove any vnet definition if exist"
	virsh net-list --all | sed -n 3~1p |
	awk '/[[:alnum:]]+/ {
		system("virsh net-destroy "$1);
		sleep 2;
		system("virsh net-undefine "$1)
	}'
	# echo "remove container if exist"
	# echo "remove images if exist"
}

sriov_config_vm_repo()
{
	$dbg_flag
	export  vm_name=$1
	if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
	vmsh run_cmd $vm_name "rm -f /etc/yum.repos.d/*"
	cat /etc/yum.repos.d/beaker-NFV.repo | awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-NFV.repo\"")}'
	cat /etc/yum.repos.d/beaker-RT.repo | awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-RT.repo\"")}'
	cat /etc/yum.repos.d/beaker-HighAvailability.repo | awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-HighAvailability.repo\"")}'
	cat /etc/yum.repos.d/beaker-CRB.repo | awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-CRB.repo\"")}'
	fi
	if (($rhel_version >= 8)); then
		vmsh run_cmd $vm_name "rm -f /etc/yum.repos.d/beaker-AppStream.repo"
		vmsh run_cmd $vm_name "rm -f /etc/yum.repos.d/beaker-BaseOS.repo"
			cat /etc/yum.repos.d/beaker-AppStream.repo | awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-AppStream.repo\"")}'
			cat /etc/yum.repos.d/beaker-BaseOS.repo | awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-BaseOS.repo\"")}'
		fi

	vmsh run_cmd $vm_name "rm -f /etc/yum.repos.d/beaker-harness.repo"
	vmsh run_cmd $vm_name "rm -f /etc/yum.repos.d/myrepo_1.repo"
	vmsh run_cmd $vm_name "rm -f /etc/yum.repos.d/beaker-kernel0.repo"
	cat /etc/yum.repos.d/beaker-harness.repo | awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-harness.repo\"")}'
	[ -f "/etc/yum.repos.d/myrepo_1.repo" ] && cat /etc/yum.repos.d/myrepo_1.repo\
		| awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/myrepo_1.repo\"")}'
	[ -f "/etc/yum.repos.d/beaker-kernel0.repo" ] && cat /etc/yum.repos.d/beaker-kernel0.repo\
		| awk '{system("vmsh run_cmd $vm_name \"echo "$0" >> /etc/yum.repos.d/beaker-kernel0.repo\"")}'
	cat /etc/resolv.conf | grep nameserver | awk '{system("vmsh run_cmd $vm_name \"echo "$2" >> /etc/resolv.conf\"")}'
	vmsh run_cmd $vm_name "service network restart;sleep 5;yum install -y kernel-kernel-networking-vnic-sriov.noarch"
	unset vm_name
}

# set up env
sriov_setup()
{
	$dbg_flag
	#use the common lib func vmsh instead of ./vmsh
	#rm -f /usr/local/bin/vmsh
	#cp ./vmsh /usr/local/bin/
	if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
	cp ${CASE_PATH}/../../common/tools/vmsh /usr/local/bin
	fi
	# stop security features
	if (($rhel_version >= 7)); then
		systemctl stop firewalld
	#	systemctl disable firewalld
	fi
	iptables -F
	ip6tables -F
	systemctl stop firewalld
	systemctl disable firewalld

	#Restarting libvirtd based on https://access.redhat.com/solutions/6071131
	systemctl restart libvirtd

	# prepare bridge shared by beaker and vm
	#local nic_bkr=$(get_default_iface)
	#echo "nic_bkr=$nic_bkr"
	#pkill dhclient
	#sleep 5
	#brctl addbr $br_bkr
	#ip link set $br_bkr up
	#brctl addif $br_bkr $nic_bkr
	#dhclient $br_bkr
	#ip addr flush dev $nic_bkr
	ip link set $nic_test up
	ip addr flush dev $nic_test
	#brctl show
	ip link show type bridge
	ip addr list

	# prepare VMs
	echo "Download guest image..."
	pushd "/var/lib/libvirt/images/" 1>/dev/null
	[ -e "$IMG_GUEST" ] || wget -nv -N $IMG_GUEST
	cp --remove-destination $(basename $IMG_GUEST) $vm1.qcow2
	cp --remove-destination $(basename $IMG_GUEST) $vm2.qcow2
	if [ "$SYS_ARCH" == "aarch" ];then
		[ -z "$IMG_FD" ] && IMG_FD=`echo $IMG_GUEST | sed 's/.qcow2/_VARS.fd/g'`
		[ -e "$IMG_FD" ] || wget -nv -N $IMG_FD
		cp --remove-destination $(basename $IMG_FD) $vm1.fd
		cp --remove-destination $(basename $IMG_FD) $vm2.fd
	fi
	ls
	popd 1>/dev/null

	# define default vnet
	virsh net-define /usr/share/libvirt/networks/default.xml
	virsh net-start default
	virsh net-autostart default
	#  ip link show | grep virbr0 || ip link add name virbr0 type bridge
	#  ip link set virbr0 up

	ip link show | grep virbr1 || ip link add name virbr1 type bridge
	ip link set virbr1 up

	echo "Create guests..."
	if [ "$SYS_ARCH" == "aarch" ];then
		workaround_swtpm
		sleep 10
		cat /etc/libvirt/qemu.conf
		yum install -y AAVMF
		pci_str=$(for i in `seq 1 15`;do echo -n "--controller type=pci,index=$i,model=pcie-root-port ";done)
		virt-install \
			--name $vm1 \
			--vcpus=2 \
			--ram=2048 \
			--disk path=/var/lib/libvirt/images/$vm1.qcow2,device=disk,bus=virtio,format=qcow2 \
			--network bridge=virbr0,model=virtio,mac=$mac4vm1 \
			--network bridge=virbr1,model=virtio,mac=$mac4vm1if2 \
			--boot loader=/usr/share/AAVMF/AAVMF_CODE.fd,loader_ro=yes,loader_type=pflash,nvram=/var/lib/libvirt/images/${vm1}.fd,loader_secure=no \
			--accelerate \
			--graphics vnc,listen=0.0.0.0 \
			--force \
			--os-variant=rhel-unknown \
			--noautoconsol \
			--controller type=pci,index=0,model=pcie-root \
			$pci_str

		virt-install \
			--name $vm2 \
			--vcpus=2 \
			--ram=2048 \
			--disk path=/var/lib/libvirt/images/$vm2.qcow2,device=disk,bus=virtio,format=qcow2 \
			--network bridge=virbr0,model=virtio,mac=$mac4vm2 \
			--boot loader=/usr/share/AAVMF/AAVMF_CODE.fd,loader_ro=yes,loader_type=pflash,nvram=/var/lib/libvirt/images/${vm2}.fd,loader_secure=no \
			--accelerate \
			--graphics vnc,listen=0.0.0.0 \
			--force \
			--os-variant=rhel-unknown \
			--noautoconsol \
			--controller type=pci,index=0,model=pcie-root \
			$pci_str
	elif [ "$SYS_ARCH" == "ppc64le" ];then
		pci_str=$(for i in `seq 1 15`;do echo -n "--controller type=pci,index=$i,model=pci-root ";done)
				virt-install \
						--name $vm1 \
						--vcpus=2 \
						--ram=2048 \
						--disk path=/var/lib/libvirt/images/$vm1.qcow2,device=disk,bus=virtio,format=qcow2 \
						--network bridge=virbr0,model=virtio,mac=$mac4vm1 \
						--network bridge=virbr1,model=virtio,mac=$mac4vm1if2 \
						--boot hd \
						--accelerate \
						--graphics vnc,listen=0.0.0.0 \
						--force \
						--os-variant=rhel-unknown \
						--noautoconsol \
						--controller type=pci,index=0,model=pci-root \
						$pci_str
				virt-install \
						--name $vm2 \
						--vcpus=2 \
						--ram=2048 \
						--disk path=/var/lib/libvirt/images/$vm2.qcow2,device=disk,bus=virtio,format=qcow2 \
						--network bridge=virbr0,model=virtio,mac=$mac4vm2 \
						--boot hd \
						--accelerate \
						--graphics vnc,listen=0.0.0.0 \
						--force \
						--os-variant=rhel-unknown \
						--noautoconsol \
						--controller type=pci,index=0,model=pci-root \
						$pci_str
	else
	#	pci_str=$(for i in `seq 1 15`;do echo -n "--controller type=pci,index=$i,model=pci-root-port ";done)
		virt-install \
			--name $vm1 \
			--vcpus=2 \
			--ram=2048 \
			--disk path=/var/lib/libvirt/images/$vm1.qcow2,device=disk,bus=virtio,format=qcow2 \
			--network bridge=virbr0,model=virtio,mac=$mac4vm1 \
			--network bridge=virbr1,model=virtio,mac=$mac4vm1if2 \
			--boot hd \
			--accelerate \
			--graphics vnc,listen=0.0.0.0 \
			--force \
			--os-variant=rhel-unknown \
			--noautoconsole \
			--import
			#--controller type=pci,index=0,model=pci-root \
			#$pci_str
		virt-install \
			--name $vm2 \
			--vcpus=2 \
			--ram=2048 \
			--disk path=/var/lib/libvirt/images/$vm2.qcow2,device=disk,bus=virtio,format=qcow2 \
			--network bridge=virbr0,model=virtio,mac=$mac4vm2 \
			--boot hd \
			--accelerate \
			--graphics vnc,listen=0.0.0.0 \
			--force \
			--os-variant=rhel-unknown \
			--noautoconsole \
			--import
			#--controller type=pci,index=0,model=pci-root \
			#$pci_str
	fi
	# wait VM bootup
	sleep 90
	#config repo

	sriov_config_vm_repo $vm1
	sriov_config_vm_repo $vm2

	# update VM kernel to the same one as host
	local k="rpm -ivh --nodeps --force $RPM_KERNEL"
	local k_core="rpm -ivh --nodeps --force $RPM_KERNEL_CORE"
	local k_modules="rpm -ivh --nodeps --force $RPM_KERNEL_MODULES"
	local k_modules_internal="rpm -ivh --nodeps --force $RPM_KERNEL_MODULES_INTERNAL"
	local yum_k="yum install -y $YUM_KERNEL"
	local yum_k_core="yum install -y $YUM_KERNEL_CORE"
	local yum_k_modules="yum install -y $YUM_KERNEL_MODULES"
	local yum_k_modules_internal="yum install -y $YUM_KERNEL_MODULES_INTERNAL"
	if (($rhel_version >= 8)); then
	vmsh run_cmd $vm1 "$k"
	vmsh run_cmd $vm1 "$k_core"
	vmsh run_cmd $vm1 "$k_modules"
	vmsh run_cmd $vm1 "$yum_k"
	vmsh run_cmd $vm1 "$yum_k_core"
	vmsh run_cmd $vm1 "$yum_k_modules"
	virsh reboot $vm1
	vmsh run_cmd $vm2 "$k"
	vmsh run_cmd $vm2 "$k_core"
	vmsh run_cmd $vm2 "$k_modules"
	vmsh run_cmd $vm2 "$yum_k"
	vmsh run_cmd $vm2 "$yum_k_core"
	vmsh run_cmd $vm2 "$yum_k_modules"
	virsh reboot $vm2
	# In rhel 8.1, modules_internal separate from modules package
	rhel_version_2=$(cat /etc/redhat-release |awk '{print $6}'| awk  'BEGIN{FS="[.:%]"} {print $2}')
	if (($rhel_version_2 >= 1 ));then
		vmsh run_cmd $vm1 "$k_modules_internal"
		vmsh run_cmd $vm2 "$k_modules_internal"
		vmsh run_cmd $vm1 "$yum_k_modules_internal"
		vmsh run_cmd $vm2 "$yum_k_modules_internal"
	fi
	else
	vmsh run_cmd $vm1 "$k"
	virsh reboot $vm1
	vmsh run_cmd $vm2 "$k"
	virsh reboot $vm2
	fi
	sleep 120
	# when running on rhel8, the vm is "in shutdown" status when get here, so add workaround for this
	if (($rhel_version == 8)); then
		virsh destroy $vm1
		virsh destroy $vm2
		sleep 2
		virsh start $vm1
		virsh start $vm2
		sleep 60
	fi
	#config repo
	#sriov_config_vm_repo $vm1
	#sriov_config_vm_repo $vm2

	# vm setup
	local cmd=(
		{iptables -F}
		{ip6tables -F}
		{systemctl stop firewalld}
		{setenforce 0}
		{yum install -y wget}
		{yum install -y tcpdump}
		{yum install -y bzip2}
		{yum install -y gcc}
		{yum install -y automake}
		{yum install -y nmap-ncat}
		{yum install -y kernel-kernel-networking-vnic-sriov}
		{source /mnt/tests/kernel/networking/common/install.sh}
		{netperf_install}
		{pkill netserver\; sleep 2\; netserver}
		# work around bz883695
		{lsmod \| grep mlx4_en \|\| modprobe mlx4_en}
		{tshark -v \&\>/dev/null \|\| yum -y install wireshark}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"
	vmsh cmd_set $vm2 "${cmd[*]}"

	if [ -n "$VM_RUN_CMD" ];then
	vmsh run_cmd $vm1 "$VM_RUN_CMD"
	vmsh run_cmd $vm2 "$VM_RUN_CMD"
	fi


	#HOST_IP=$(cat /usr/share/libvirt/networks/default.xml|grep "ip address"|awk -F" " '{print $2}'|awk -F"\"" '{print $2}')
	#GUEST_IP=$(cat /usr/share/libvirt/networks/default.xml|grep "range start="|awk -F" " '{print $2}'|awk -F"\"" '{print $2}')
	#vmsh change_local_passwd redhat

	if (($rhel_version >= 7)); then
		vmsh run_cmd $vm1 "systemctl stop NetworkManager"
	#	vmsh run_cmd $vm1 "systemctl disable NetworkManager"
		vmsh run_cmd $vm2 "systemctl stop NetworkManager"
	#	vmsh run_cmd $vm2 "systemctl disable NetworkManager"
	fi

	virsh autostart $vm1
	virsh autostart $vm2
}

sriov_setup_container()
{
	$dbg_flag
	#get image
	for time in `seq 0 5`
	do
		echo "Download container image..."
		if [ "$SYS_ARCH" == "aarch" ];then
			wget -nv -N http://netqe-infra01.knqe.lab.eng.bos.redhat.com/container_images/container_sriov_centos_stream8_aarch64.tar
			podman load --input container_sriov_centos_stream8_aarch64.tar
			if [ $? -eq 0 ]
			then
				#create container
				podman run --privileged --name $container1 -it  -d $c_image_arm sleep infinity
				podman run --privileged --name $container2 -it  -d $c_image_arm sleep infinity
				#check the contaiers
				podman ps
				podman exec $container1 yum install -y iproute
				podman exec $container2 yum install -y iproute
				podman exec $container1 yum install -y iperf3
				podman exec $container2 yum install -y iperf3
				return 0
			else
				sleep 5
			fi
		elif [ "$SYS_ARCH" == "ppc64le" ];then
			wget -nv -N http://netqe-infra01.knqe.lab.eng.bos.redhat.com/container_images/centos_stream8_ppc64le.tar
			podman load --input centos_stream8_ppc64le.tar
			if [ $? -eq 0 ]
			then
				#create container
				podman run --privileged --name $container1 -it  -d $c_image_ppc64le sleep infinity
				podman run --privileged --name $container2 -it  -d $c_image_ppc64le sleep infinity
				#check the contaiers
				podman ps
				podman exec $container1 yum install -y iproute
				podman exec $container2 yum install -y iproute
				podman exec $container1 yum install -y iperf3
				podman exec $container2 yum install -y iperf3
				return 0
			else
				sleep 5
			fi
		else
			wget -nv -N http://netqe-infra01.knqe.lab.eng.bos.redhat.com/container_images/container_sriov_centos8.tar
			podman load --input container_sriov_centos8.tar
			if [ $? -eq 0 ]
			then
				#create container
				podman run --privileged --name $container1 -it  -d $c_image sleep infinity
				podman run --privileged --name $container2 -it  -d $c_image sleep infinity
				#check the contaiers
				podman ps
				return 0
			else
				sleep 5
			fi
		fi
	done
		return 1
}

sriov_setup_pod_container()
{
	echo "######sriov_setup_pod_container#######"
	#create pod
	podman pod create --name $pod1
	podman pod create --name $pod2

	#check pod
	echo "####check the pod via 'podman pod ps'####"
	podman pod ps

	#get image
	for time in `seq 0 5`
	do
		echo "####Download container image...####"
		if [ "$SYS_ARCH" == "aarch" ];then
			wget -nv -N -c -t 3 http://netqe-infra01.knqe.lab.eng.bos.redhat.com/container_images/container_sriov_centos_stream8_aarch64.tar
			podman load --input container_sriov_centos_stream8_aarch64.tar
			if [ $? -eq 0 ]
			then
				echo "####add container to the pod####"
				podman run  --privileged -dt --name $container1 --pod $pod1 $c_image_arm sleep infinity
				podman run  --privileged -dt --name $container2 --pod $pod1 $c_image_arm sleep infinity
				podman run  --privileged -dt --name $container3 --pod $pod2 $c_image_arm sleep infinity
				podman run  --privileged -dt --name $container4 --pod $pod2 $c_image_arm sleep infinity
				echo "####check the contaiers via 'podman ps -a --pod'####"
				podman ps -a --pod
				podman exec $container1 yum install -y iproute iperf3
				podman exec $container2 yum install -y iproute iperf3
				podman exec $container3 yum install -y iproute iperf3
				podman exec $container4 yum install -y iproute iperf3
				return 0
			else
				sleep 5
			fi
		elif [ "$SYS_ARCH" == "ppc64le" ];then
			wget -nv -N -c -t 3 http://netqe-infra01.knqe.lab.eng.bos.redhat.com/container_images/centos_stream8_ppc64le.tar
			podman load --input centos_stream8_ppc64le.tar
			if [ $? -eq 0 ]
			then
				echo "####add container to the pod####"
				podman run  --privileged -dt --name $container1 --pod $pod1 $c_image_ppc64le sleep infinity
				podman run  --privileged -dt --name $container2 --pod $pod1 $c_image_ppc64le sleep infinity
				podman run  --privileged -dt --name $container3 --pod $pod2 $c_image_ppc64le sleep infinity
				podman run  --privileged -dt --name $container4 --pod $pod2 $c_image_ppc64le sleep infinity
				echo "####check the contaiers via 'podman ps -a --pod'####"
				podman ps -a --pod
				podman exec $container1 yum install -y iproute
				podman exec $container2 yum install -y iproute
				podman exec $container3 yum install -y iproute
				podman exec $container4 yum install -y iproute
				return 0
			else
				sleep 5
			fi
		else
			wget -nv -N -c -t 3 http://netqe-infra01.knqe.lab.eng.bos.redhat.com/container_images/container_sriov_centos8.tar
			podman load --input container_sriov_centos8.tar
			if [ $? -eq 0 ]
			then
				echo "####add container to the pod####"
				podman run  --privileged -dt --name $container1 --pod $pod1 $c_image sleep infinity
				podman run  --privileged -dt --name $container2 --pod $pod1 $c_image sleep infinity
				podman run  --privileged -dt --name $container3 --pod $pod2 $c_image sleep infinity
				podman run  --privileged -dt --name $container4 --pod $pod2 $c_image sleep infinity
				echo "####check the contaiers via 'podman ps -a --pod'####"
				podman ps -a --pod
				return 0
			else
				sleep 5
			fi
		fi
	done
	return 1
}

get_test_nic(){
	local NIC_NUM=$1
	if [[ $# -ge 2 ]]; then
		for i in `seq 1 ${NIC_NUM}`; do
			if [[ -n $2 ]]; then
				nic_list[i]=$2
				shift
			else
				rlFail "FATAL ERROR: nic_list is not availabe!"
				exit 1
			fi
		done
		echo "${nic_list[*]}"
	else
			nic_list=($(get_required_iface))
			if [[ -z "${nic_list[*]}" ]]; then
					rlFail "FATAL ERROR: nic_list is not availabe!"
					exit 1
			fi
			echo "${nic_list[*]}"
	fi
	return 0

}

sriov_clean_pod_container()
{
	set -x
	podman pod ps --format '{{.ID}}' | xargs -I {} podman pod stop {}
	podman pod ps --format '{{.ID}}' | xargs -I {} podman pod rm {}
	podman ps --all --format '{{.ID}}' | xargs -I {} podman stop {}
	podman ps --all --format '{{.ID}}' | xargs -I {} podman rm {}
	podman image list --format '{{.ID}}' | xargs -I {} podman image rm {}
	set +x
}

sriov_config_dpdk()
{
	yum install -y pciutils
	if [ ! -e /usr/bin/python ];then
		if [ -e "/usr/libexec/platform-python" ];then
				ln -s /usr/libexec/platform-python /usr/bin/python
		elif [ -e "/usr/bin/python2" ];then
				ln -s /usr/bin/python2 /usr/bin/python
		fi
	fi

	rpm -ivh $DPDK_URL
	rpm -ivh $DPDK_TOOLS_URL
	local hugepage_free=$(cat /proc/meminfo |grep HugePages_Total|awk '{print $2}')
	local hugepage_size=$(cat /proc/meminfo |grep Hugepagesize|awk '{print $2}')
	#use 1G hugepage size and reserve 24 pages
	if [ $hugepage_free -ne 24 -o $hugepage_size -ne 1048576 ];then
		grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24" --update-kernel=$(grubby --default-kernel)
#		sed -i 's/default_hugepagesz=[0-9]\+[MGmg]//g'  /etc/default/grub
#		sed -i 's/hugepagesz=[0-9]\+[MGmg]//g'  /etc/default/grub
#		sed -i 's/hugepages=[0-9]\+//g'  /etc/default/grub
#		sed -i 's:GRUB_CMDLINE_LINUX="\(.*\)":GRUB_CMDLINE_LINUX="\1 default_hugepagesz=1G hugepagesz=1G hugepages=24":' /etc/default/grub
#		grub2-mkconfig -o /boot/grub2/grub.cfg
		#workaround for mlx4_en nic
		yum install -y libibverbs
		echo options mlx4_core log_num_mgm_entry_size=-1  >> /etc/modprobe.d/mlx4.conf
		dracut -f -v
		rhts-reboot
	fi
	[ -e /mnt/huge ] || mkdir /mnt/huge
	mount -t hugetlbfs nodev /mnt/huge
	modprobe vfio-pci
}


###############################

sriov_test_pf_remote()
{
	$dbg_flag
	log_header "PF($nic_test) <---> REMOTE" $result_file $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_pf_remote_start
		sync_wait client test_pf_remote_end

		ip addr flush $nic_test
	else
		if ! sriov_create_vfs $nic_test 0 2; then
			sync_wait server test_pf_remote_start
			sync_set server test_pf_remote_end
			return 1
		fi

		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		ip -d link show $nic_test
		ip -d addr show $nic_test

		sync_wait server test_pf_remote_start
		do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
		result=$?
		sync_set server test_pf_remote_end

		ip addr flush $nic_test
		sriov_remove_vfs $nic_test 0
	fi


	return $result
}

sriov_test_pf_remote_jumbo()
{
	$dbg_flag
	log_header "PF($nic_test) <---> REMOTE JUMBO" $result_file $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip link set mtu 9000 dev $nic_test
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_pf_remote_start
		sync_wait client test_pf_remote_end

		ip link set mtu 1500 dev $nic_test
		ip addr flush $nic_test
	else
		if ! sriov_create_vfs $nic_test 0 2; then
			sync_wait server test_pf_remote_start
			sync_set server test_pf_remote_end
			return 1
		fi


		ip link set mtu 9000 dev $nic_test || result=1
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		ip -d link show $nic_test
		ip -d addr show $nic_test

		sync_wait server test_pf_remote_start
		do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
		let result+=$?
		sync_set server test_pf_remote_end

		ip link set mtu 1500 dev $nic_test
		ip addr flush $nic_test
		sriov_remove_vfs $nic_test 0
	fi


	return $result
}

sriov_test_pf_vlan_remote()
{
	$dbg_flag
	log_header "PF VLAN($nic_test.$vid) <---> REMOTE" $result_file

	local result=0
	local vid=3

	ip link set $nic_test up

	if i_am_server; then
		ip link add link $nic_test name $nic_test.$vid type vlan id $vid
		ip link set $nic_test.$vid up

		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr_vlan}.2/24 dev $nic_test.${vid}
		ip addr add 2021:db8:${ipaddr_vlan}::2/64 dev $nic_test.${vid}

		sync_set client test_pf_vlan_remote_start
		sync_wait client test_pf_vlan_remote_end

		ip link set ${nic_test}.${vid} down
		ip link del ${nic_test}.${vid}
	else
		sync_wait server test_pf_vlan_remote_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_pf_vlan_remote_end
			return 1
		fi

		ip link add link $nic_test name $nic_test.$vid type vlan id $vid
		ip link set $nic_test.$vid up

		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr_vlan}.1/24 dev $nic_test.${vid}
		ip addr add 2021:db8:${ipaddr_vlan}::1/64 dev $nic_test.${vid}
		ip -d link show $nic_test.${vid}
		ip -d addr show $nic_test.${vid}

		do_host_netperf 172.30.${ipaddr_vlan}.2 2021:db8:${ipaddr_vlan}::2 $result_file
		result=$?

		ip link set ${nic_test}.${vid} down
		ip link del ${nic_test}.${vid}

		sriov_remove_vfs $nic_test 0

		sync_set server test_pf_vlan_remote_end
	fi

	return $result
}

sriov_test_vf_remote()
{
	$dbg_flag
	log_header "VF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vf_remote_start
		sync_wait client test_vf_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vf_remote_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_remote_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			echo "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
				#workaround for ionic bz1914175
				ip link set dev $vf address 00:de:ad:$(printf "%02x" $ipaddr):01:01
				ip link set $vf down
				sleep 2
			fi
			ip link set $vf up
			sleep 5
			ip addr flush $vf
			ip addr add 172.30.${ipaddr}.1/24 dev $vf
			ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
			ip -d link show $vf
			ip -d addr show $vf

			do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			local result=$?

			ip addr flush $vf
		fi
		sriov_remove_vfs $nic_test 0

		sync_set server test_vf_remote_end
	fi

	return $result
}

sriov_test_vf_remote_switchdev()
{
	log_header "VF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vf_remote_switchdev_start 14400
		sync_wait client test_vf_remote_switchdev_end  14400

		ip addr flush $nic_test
	else
		#sync_wait server test_vf_remote_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family' 'Intel-Ethernet_Controller_E810C_for_QSFP' 'Intel-Ethernet_Controller_E810C_for_SFP' 'Intel-Ethernet_Controller_E810C_for_backplane' 'Intel-Ethernet_Controller_E810XXV_for_SFP)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			switchdev_setup_nfp
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
						ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi
			sync_wait server test_vf_remote_switchdev_start 14400

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_vf_remote_switchdev_end 14400
				return 1
			fi

			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			if [ -z "$vf" ]; then
				echo "FAILED to get VF interface"
				result=1
			else
				ethtool -i $vf

				if sriov_vfmac_is_zero $nic_test 0 1; then
					ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
					ip link set $vf down
					sleep 2
				fi

				switchdev_setup_mlx
				#workaround for bz1877274
				nic_test=$(get_required_iface)
				ip link set $nic_test up
				sleep 2
				ip link show $nic_test

				local reps=$(switchdev_get_reps $nic_test)
				if [ -z "$reps" ]; then
					echo "FAILED to get representor"
					result=1
				else
					ip link set $nic_test master hostbr0
					echo "rep list $reps"
					for rep in $reps
					do
						ip link show $rep
						ip link set $rep up
						ip link set $rep master hostbr0
						rlRun "nmcli device set $rep managed no"
					done
					ip link set $vf up
					sleep 5
					ip link show
					ip addr flush $vf
					ip addr add 172.30.${ipaddr}.1/24 dev $vf
					ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
					ip -d link show $vf
					ip -d addr show $vf

					do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
					local result=$?

					ip addr flush $vf
				fi
			fi

			switchdev_cleanup_mlx
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0

			sync_set server test_vf_remote_switchdev_end 14400
		else
			sync_wait server test_vf_remote_switchdev_start 14400
			sync_set server test_vf_remote_switchdev_end 14400
		fi
	fi

	return $result
}

sriov_test_vf_remote_jumbo()
{
	log_header "VF <---> REMOTE JUMBO" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip link set mtu 9000 dev $nic_test
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vf_remote_start
		sync_wait client test_vf_remote_end

		ip addr flush $nic_test
		ip link set mtu 1500 dev $nic_test
	else
		sync_wait server test_vf_remote_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_remote_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			echo "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
				#workaround for ionic bz1914175
				ip link set dev $vf address 00:de:ad:$(printf "%02x" $ipaddr):01:01
				ip link set $vf down
				sleep 2
			fi
			ip link set $vf up
			sleep 10
			ip link set mtu 9000 dev $nic_test
			sleep 10
			ip link set mtu 9000 dev $vf || result=1
			sleep 10
			ip addr flush $vf
			sleep 1
			ip addr add 172.30.${ipaddr}.1/24 dev $vf
			sleep 1
			ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
			sleep 1
			ip -d link show $vf
			ip -d addr show $vf

			do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			let result+=$?

			ip link set mtu 1500 dev $vf
			ip link set mtu 1500 dev $nic_test
			ip addr flush $vf
		fi
		sriov_remove_vfs $nic_test 0

		sync_set server test_vf_remote_end
	fi

	return $result
}

sriov_test_vf_vlan_remote()
{
	$dbg_flag
	log_header "VF VLAN <---> REMOTE" $result_file

	local result=0
	local vid=3

	ip link set $nic_test up

	if i_am_server; then
		ip link add link $nic_test name ${nic_test}.${vid} type vlan id $vid
		ip link set ${nic_test}.${vid} up
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr_vlan}.2/24 dev $nic_test.$vid
		ip addr add 2021:db8:${ipaddr_vlan}::2/64 dev $nic_test.$vid

		sync_set client test_vf_vlan_remote_start
		sync_wait client test_vf_vlan_remote_end

		ip link set ${nic_test}.${vid} down
		ip link del ${nic_test}.${vid}
	else
		sync_wait server test_vf_vlan_remote_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_vlan_remote_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			echo "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf %02x ${ipaddr}):01:01
				ip link set $vf down
				sleep 2
			fi

			ip link set $vf up
			sleep 5
			ip link add link $vf name ${vf}.${vid} type vlan id $vid
			ip link set ${vf}.${vid} up
			ip addr flush $vf
			ip addr add 172.30.${ipaddr_vlan}.1/24 dev ${vf}.${vid}
			ip addr add 2021:db8:${ipaddr_vlan}::1/64 dev ${vf}.${vid}
			ip link show ${vf}.${vid}
			ip addr show ${vf}.${vid}

			do_host_netperf 172.30.${ipaddr_vlan}.2 2021:db8:${ipaddr_vlan}::2 $result_file
			result=$?

			ip link set ${vf}.${vid} down
			ip link del ${vf}.${vid}
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vf_vlan_remote_end
	fi

	return $result
}

sriov_test_vmvf_remote()
{
	$dbg_flag
	log_header "VMVF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmvf_remote_start
		sync_wait client test_vmvf_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_remote_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_remote_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			result=$?

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_remote_end
	fi

	return $result
}

#two vfs from the same pf on one vm
sriov_test_vmvf1vf2_same_pf_remote()
{
	log_header "VMVF1VF2 <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmvf1vf2_same_pf_remote_start
		sync_wait client test_vmvf1vf2_same_pf_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf1vf2_same_pf_remote_start

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf1vf2_same_pf_remote_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac1 ||
			! sriov_attach_vf_to_vm $nic_test 0 2 $vm1 $mac2; then
			result=1
		else
			local cmd=(
				{export NIC_TEST1=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST1 up}
				{ip addr flush \$NIC_TEST1}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST1}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST1}
				{ip link show \$NIC_TEST1}
				{ip addr show \$NIC_TEST1}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			rlLog "CHECK THE FIRST VF CONNECTION"
			do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			result=$?
			local cmd=(
				{export NIC_TEST1=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST1 up}
				{ip addr flush \$NIC_TEST1}
				)
			vmsh cmd_set $vm1 "${cmd[*]}"
			rlLog "CHECK THE FIRST VF CONNECTION FINISH"

			local cmd=(
				{export NIC_TEST2=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST2 up}
				{ip addr flush \$NIC_TEST2}
				{ip addr add 172.30.${ipaddr}.12/24 dev \$NIC_TEST2}
				{ip addr add 2021:db8:${ipaddr}::12/64 dev \$NIC_TEST2}
				{ip link show \$NIC_TEST2}
				{ip addr show \$NIC_TEST2}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			echo "CHECK THE SECOND VF CONNECTION"
			do_vm_netperf $vm1 172.30.${ipaddr}.12,172.30.${ipaddr}.2 2021:db8:${ipaddr}::12,2021:db8:${ipaddr}::2 $result_file
			let result+=$?
			local cmd=(
				{export NIC_TEST2=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST2 up}
				{ip addr flush \$NIC_TEST2}
				)
			vmsh cmd_set $vm2 "${cmd[*]}"
			rlLog "CHECK THE FIRST VF CONNECTION FINISH"

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			sriov_detach_vf_from_vm $nic_test 0 2 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf1vf2_same_pf_remote_end
	fi

	return $result
}

sriov_test_1733181_vmvf_remote_pfdown()
{
	log_header "VMVF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmvf_remote_start
		sync_wait client test_vmvf_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_remote_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_vmvf_remote_end
			return 1
		fi

		if [[ "$NIC_DRIVER" == "i40e" ]] || [[ "$NIC_DRIVER" == "ice" ]];then
			ethtool --set-priv-flags $nic_test link-down-on-close on
			ethtool --show-priv-flags $nic_test
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			vmsh run_cmd $vm1 "timeout 20s bash -c \"until ping -c3 172.30.${ipaddr}.2; do sleep 5; done\""
			result=$?
			if [ $result -ne 0 ]; then echo "FAILED: PING FAILED WITH PF UP"; fi
			echo "########ip link set pf down####### "
			ip link set $nic_test down
			echo "########check the pf link state########"
			ip link show $nic_test
			ip link show $nic_test | grep "link-state auto"
			if [ $? -ne 0 ]; then echo "FAILED: LINK_STATE IS NOT AUTO BY DEFAULT"; fi
			let result+=$?
			echo "#########check connection with pf down and vf link-state auto############"
			vmsh run_cmd $vm1 "timeout 20s bash -c \"until ping -c3 172.30.${ipaddr}.2; do sleep 5; done\""
			if [ $? -eq 0 ]; then let result+=1; echo "FAILED: VF still sending traffic when PF is down and link state is auto"; fi
			vmsh run_cmd $vm1 "timeout 20s bash -c \"until ping6 -c3 2021:db8:${ipaddr}::2; do sleep 5; done\""
			if [ $? -eq 0 ]; then let result+=1; echo "FAILED: VF still sending traffic when PF is down and link state is auto";fi
			echo "#########set vf link state to disable and check#########"
			ip link set $nic_test vf 0 state disable
			ip link show $nic_test | grep "link-state disable"
			if [ $? -ne 0 ]; then echo "FAILED: LINK_STATE IS NOT DISABLE"; fi
			let result+=$?
			echo "#########check connection with pf down and vf link-state disable#######"
			vmsh run_cmd $vm1 "timeout 20s bash -c \"until ping -c3 172.30.${ipaddr}.2; do sleep 5; done\""
			if [ $? -eq 0 ]; then let result+=1;echo "FAILED: VF still sending traffic when PF is down and link state is disable"; fi
			vmsh run_cmd $vm1 "timeout 20s bash -c \"until ping6 -c3 2021:db8:${ipaddr}::2; do sleep 5; done\""
			if [ $? -eq 0 ]; then let result+=1; echo "FAILED: VF still sending traffic when PF is down and link state is disable";fi
			echo "#########set vf link state to enable and check##########"
			ip link set $nic_test vf 0 state enable
			ip link show $nic_test | grep "link-state enable"
			if [ $? -ne 0 ]; then echo "FAILED: LINK_STATE IS NOT ENABLE"; fi
			let result+=$?
			echo "########check connection with pf down and vf link-state enable##########"
			vmsh run_cmd $vm1 "timeout 20s bash -c \"until ping -c3 172.30.${ipaddr}.2; do sleep 5; done\""
			if [ $? -eq 0 ]; then let result+=1; echo "FAILED: VF still sending traffic when PF is down and link state is enable";fi
			vmsh run_cmd $vm1 "timeout 20s bash -c \"until ping6 -c3 2021:db8:${ipaddr}::2; do sleep 5; done\""
			if [ $? -eq 0 ]; then let result+=1; echo "FAILED: VF still sending traffic when PF is down and link state is enable";fi

			ip link set $nic_test vf 0 state auto
			ip link set $nic_test up
			sleep 5
			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0
		if [[ "$NIC_DRIVER" == "i40e" ]] || [[ "$NIC_DRIVER" == "ice" ]];then
			ethtool --set-priv-flags $nic_test link-down-on-close off
			ethtool --show-priv-flags $nic_test
			ip link set $nic_test up
			ip link show $nic_test
		fi

		sync_set server test_vmvf_remote_end
	fi
	return $result
}

sriov_test_vmvf_remote_jumbo()
{
	log_header "VMVF <---> REMOTE (JUMBO)" $result_file

	local result=0

	ip link set $nic_test up
	ip link set mtu 9000 dev $nic_test || result=1

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmvf_remote_jumbo_start
		sync_wait client test_vmvf_remote_jumbo_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_remote_jumbo_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			result=1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			ip link set mtu 9000 dev $nic_test || result=1
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip link set mtu 9000 \$NIC_TEST}
				{sleep 5}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			result=$?

			do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file "" "16384,16384"
			let result+=$?

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_remote_jumbo_end
	fi

	ip link set mtu 1500 dev $nic_test

	return $result
}

# vlan interface created on VF in VM
sriov_test_vmvf_vlan_remote()
{
	log_header "VMVF VLAN <---> REMOTE" $result_file

	local result=0
	local vid=3

	ip link set $nic_test up

	if i_am_server; then
		ip link add link $nic_test name ${nic_test}.${vid} type vlan id $vid
		ip link set ${nic_test}.${vid} up
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr_vlan}.2/24 dev $nic_test.$vid
		ip addr add 2021:db8:${ipaddr_vlan}::2/64 dev $nic_test.$vid

		sync_set client test_vmvf_vlan_remote_start
		sync_wait client test_vmvf_vlan_remote_end

		ip link set ${nic_test}.${vid} down
		ip link del ${nic_test}.${vid}
	else
		sync_wait server test_vmvf_vlan_remote_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_vlan_remote_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$vid type vlan id $vid}
				{ip link set \$NIC_TEST.$vid up}
				{ip addr flush \$NIC_TEST.$vid}
				{ip addr add 172.30.${ipaddr_vlan}.11/24 dev \$NIC_TEST.$vid}
				{ip addr add 2021:db8:${ipaddr_vlan}::11/64 dev \$NIC_TEST.$vid}
				{ip link show \$NIC_TEST.$vid}
				{ip addr show \$NIC_TEST.$vid}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			do_vm_netperf $vm1 172.30.${ipaddr_vlan}.2 2021:db8:${ipaddr_vlan}::2 $result_file
			result=$?

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_vlan_remote_end
	fi

	return $result
}

sriov_test_vmvf_vlan_remote_jumbo()
{
	log_header "VMVF VLAN <---> REMOTE (JUMBO)" $result_file

	local result=0
	local vid=3

	ip link set $nic_test up
	ip link set mtu 9000 $nic_test || result=1

	if i_am_server; then
		ip link add link $nic_test name ${nic_test}.${vid} type vlan id $vid
		ip link set ${nic_test}.${vid} up
		ip link set mtu 9000 $nic_test.${vid}

		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr_vlan}.2/24 dev $nic_test.$vid
		ip addr add 2021:db8:${ipaddr_vlan}::2/64 dev $nic_test.$vid

		sync_set client test_vmvf_vlan_remote_jumbo_start
		sync_wait client test_vmvf_vlan_remote_jumbo_end

		ip link set ${nic_test}.${vid} down
		ip link del ${nic_test}.${vid}
	else
		sync_wait server test_vmvf_vlan_remote_jumbo_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_vlan_remote_jumbo_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			sriov_remove_vfs $nic_test 0
			sync_set server test_vmvf_vlan_remote_jumbo_end
			return 1
		fi

		ip link set mtu 9000 $nic_test || result=1

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip link set mtu 9000 dev \$NIC_TEST}
			{sleep 5}
			{ip addr flush \$NIC_TEST}
			{ip link add link \$NIC_TEST name \$NIC_TEST.$vid type vlan id $vid}
			{ip link set \$NIC_TEST.$vid up}
			{ip link set mtu 9000 dev \$NIC_TEST.$vid}
			{ip addr flush \$NIC_TEST.$vid}
			{ip addr add 172.30.${ipaddr_vlan}.11/24 dev \$NIC_TEST.$vid}
			{ip addr add 2021:db8:${ipaddr_vlan}::11/64 dev \$NIC_TEST.$vid}
			{ip link show \$NIC_TEST.$vid}
			{ip addr show \$NIC_TEST.$vid}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		result=$?

		do_vm_netperf $vm1 172.30.${ipaddr_vlan}.2 2021:db8:${ipaddr_vlan}::2 $result_file
		let result+=$?

		sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_vlan_remote_jumbo_end
	fi

	ip link set mtu 1500 $nic_test

	return $result
}

# set vlan in XML for 'virsh attach-device'
sriov_test_vmvf_vlan_remote_1()
{
	log_header "VMVF VLAN <---> REMOTE - 1" $result_file

	local result=0
	local vid=3

	local old_sriov_use_hostdev=$SRIOV_USE_HOSTDEV
	SRIOV_USE_HOSTDEV=no

	ip link set $nic_test up

	if i_am_server; then
		ip link add link $nic_test name ${nic_test}.${vid} type vlan id $vid
		ip link set ${nic_test}.${vid} up
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr_vlan}.2/24 dev $nic_test.$vid
		ip addr add 2021:db8:${ipaddr_vlan}::2/64 dev $nic_test.$vid

		sync_set client test_vmvf_vlan_remote_1_start
		sync_wait client test_vmvf_vlan_remote_1_end

		ip link set ${nic_test}.${vid} down
		ip link del ${nic_test}.${vid}
	else
		sync_wait server test_vmvf_vlan_remote_1_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_vlan_remote_1_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac $vid; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr_vlan}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr_vlan}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			do_vm_netperf $vm1 172.30.${ipaddr_vlan}.2 2021:db8:${ipaddr_vlan}::2 $result_file
			result=$?

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_vlan_remote_1_end
	fi

	SRIOV_USE_HOSTDEV=$old_sriov_use_hostdev

	return $result
}

sriov_test_pf_vmvf()
{
	$dbg_flag
	log_header "PF <---> VMVF" $result_file

	if i_am_server; then
		sync_set client test_pf_vmvf_start
		sync_wait client test_pf_vmvf_end
		return 0
	fi

	sync_wait server test_pf_vmvf_start

	local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_pf_vmvf_end
		return 1
	fi

	# setup pf
	ip link set $nic_test up
	ip addr flush $nic_test
	ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
	ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
	ip -d link show $nic_test
	ip -d addr show $nic_test

	# setup vmvf
	if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
		sync_set server test_pf_vmvf_end
		return 1
	fi

	#ensure netserver is running
	local cmd=(
		{iptables -F}
		{ip6tables -F}
		{systemctl stop firewalld}
		{pkill netserver\; sleep 2\; netserver}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
		{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
		{ip link show \$NIC_TEST}
		{ip addr show \$NIC_TEST}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# test
	local result=0
	if ! do_host_netperf 172.30.${ipaddr}.11 2021:db8:${ipaddr}::11 $result_file; then
		result=1
	fi
	if ! do_vm_netperf $vm1 172.30.${ipaddr}.1 2021:db8:${ipaddr}::1 $result_file; then
		result=1
	fi

	# cleanup
	sriov_detach_vf_from_vm $nic_test 0 1 $vm1
	ip addr flush $nic_test
	sriov_remove_vfs $nic_test 0

	sync_set server test_pf_vmvf_end

	return $result
}

sriov_test_pf_vmvf_vlan()
{
	$dbg_flag
	log_header "PF <---> VMVF VLAN" $result_file

	if i_am_server; then
		sync_set client test_pf_vmvf_vlan_start
		sync_wait client test_pf_vmvf_vlan_end
		return 0
	fi

	sync_wait server test_pf_vmvf_vlan_start

	local vid=3
	local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_pf_vmvf_vlan_end
		return 1
	fi

	# setup pf
	ip link set $nic_test up
	ip addr flush $nic_test
	ip link add link $nic_test name $nic_test.$vid type vlan id $vid
	ip link set $nic_test.$vid up
	ip addr flush $nic_test.$vid
	ip addr add 172.30.${ipaddr_vlan}.1/24 dev $nic_test.$vid
	ip addr add 2021:db8:${ipaddr_vlan}::1/64 dev $nic_test.$vid
	ip -d link show $nic_test.$vid
	ip -d addr show $nic_test.$vid

	# setup vmvf
	if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
		sync_set server test_pf_vmvf_vlan_end
		return 1
	fi
	#ensure netserver is running
	local cmd=(
		{iptables -F}
		{ip6tables -F}
		{systemctl stop firewalld}
		{pkill netserver\; sleep 2\; netserver}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"


	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip link add link \$NIC_TEST name \$NIC_TEST.$vid type vlan id $vid}
		{ip link set \$NIC_TEST.$vid up}
		{ip addr flush \$NIC_TEST.$vid}
		{ip addr add 172.30.${ipaddr_vlan}.11/24 dev \$NIC_TEST.$vid}
		{ip addr add 2021:db8:${ipaddr_vlan}::11/64 dev \$NIC_TEST.$vid}
		{ip link show \$NIC_TEST.$vid}
		{ip addr show \$NIC_TEST.$vid}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# test
	local result=0
	if ! do_host_netperf 172.30.${ipaddr_vlan}.11 2021:db8:${ipaddr_vlan}::11 $result_file; then
		result=1
	fi

	if ! do_vm_netperf $vm1 172.30.${ipaddr_vlan}.1 2021:db8:${ipaddr_vlan}::1 $result_file; then
		result=1
	fi

	# cleanup
	sriov_detach_vf_from_vm $nic_test 0 1 $vm1
	ip link set $nic_test.$vid down
	ip link del $nic_test.$vid
	sriov_remove_vfs $nic_test 0

	sync_set server test_pf_vmvf_vlan_end

	return $result
}

# two VFs on same PF
sriov_test_vmvf_vmvf()
{
	log_header "VMVF <---> VMVF" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		sync_set client test_vmvf_vmvf_start
		sync_wait client test_vmvf_vmvf_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_vmvf_vmvf_start

	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"

	sriov_create_vfs $nic_test 0 2
	# The current attach vf operation will restart the vm and put any operations after the vm started.
	if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac1; then
		sync_set server test_vmvf_vmvf_end
		return 1
	fi

	if ! sriov_attach_vf_to_vm $nic_test 0 2 $vm2 $mac2; then
		sync_set server test_vmvf_vmvf_end
		return 1
	fi

	#ensure netserver is running
	local cmd=(
			{iptables -F}
			{ip6tables -F}
			{systemctl stop firewalld}
			{pkill netserver\; sleep 2\; netserver}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"
	vmsh cmd_set $vm2 "${cmd[*]}"

	# setup vmvf1

	local cmd=(
	{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
	{ip link set \$NIC_TEST up}
	{ip addr flush \$NIC_TEST}
	{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
	{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
	{ip link show \$NIC_TEST}
	{ip addr show \$NIC_TEST}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# setup vmvf2

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip addr add 172.30.${ipaddr}.21/24 dev \$NIC_TEST}
		{ip addr add 2021:db8:${ipaddr}::21/64 dev \$NIC_TEST}
		{ip link show \$NIC_TEST}
		{ip addr show \$NIC_TEST}
	)
	vmsh cmd_set $vm2 "${cmd[*]}"

	# test
	local result=0
	if ! do_vm_netperf $vm1 172.30.${ipaddr}.21 2021:db8:${ipaddr}::21 $result_file; then
		result=1
	fi
	if ! do_vm_netperf $vm2 172.30.${ipaddr}.11 2021:db8:${ipaddr}::11 $result_file; then
		result=1
	fi
	if ! do_vm_netperf $vm1 172.30.${ipaddr}.1 2021:db8:${ipaddr}::1 $result_file; then
		result=1
	fi
	if ! do_vm_netperf $vm2 172.30.${ipaddr}.1 2021:db8:${ipaddr}::1 $result_file; then
		result=1
	fi

	# clearnup
	sriov_detach_vf_from_vm $nic_test 0 1 $vm1
	sriov_detach_vf_from_vm $nic_test 0 2 $vm2

	sriov_remove_vfs $nic_test 0

	sync_set server test_vmvf_vmvf_end

	return $result
}

# two VFs on same PF
sriov_test_vmvf_vmvf_vlan()
{
	log_header "VMVF <---> VMVF VLAN with same PF" $result_file
	local vid=3
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"
	echo "mac1=${mac1}"
	echo "mac2=${mac2}"


	if i_am_server; then
	ip link set $nic_test up
		ip link add link $nic_test name ${nic_test}.${vid} type vlan id $vid
		ip link set ${nic_test}.${vid} up
		ip addr add 172.30.${ipaddr_vlan}.1/24 dev ${nic_test}.${vid}
		ip addr add 2021:db8:${ipaddr_vlan}::1/64 dev ${nic_test}.${vid}
		ip link set ${nic_test}.${vid} up
		ip addr show ${nic_test}.${vid}
		pkill -9 netserver && sleep 2 && netserver
		sync_set client test_vmvf_vmvf_vlan_start
		sync_wait client test_vmvf_vmvf_vlan_end
		ip link del ${nic_test}.${vid}
		return 0
	fi

	sync_wait server test_vmvf_vmvf_vlan_start

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_vmvf_vmvf_vlan_end
		return 1
	fi

	# The current attach vf operation will restart the vm and put any operations after the vm started.
	if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac1; then
		sync_set server test_vmvf_vmvf_vlan_end
		return 1
	fi

	if ! sriov_attach_vf_to_vm $nic_test 0 2 $vm2 $mac2; then
		sync_set server test_vmvf_vmvf_vlan_end
		return 1
	fi

		#ensure netserver is running
	local cmd=(
			{iptables -F}
			{ip6tables -F}
			{systemctl stop firewalld}
			{pkill netserver\; sleep 2\; netserver}
			{ip a}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"
	vmsh cmd_set $vm2 "${cmd[*]}"

	# setup vmvf1

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip link add link \$NIC_TEST name \$NIC_TEST.$vid type vlan id $vid}
		{ip link set \$NIC_TEST.$vid up}
		{ip addr flush \$NIC_TEST.$vid}
		{ip addr add 172.30.${ipaddr_vlan}.11/24 dev \$NIC_TEST.$vid}
		{ip addr add 2021:db8:${ipaddr_vlan}::11/64 dev \$NIC_TEST.$vid}
		{ip link set \$NIC_TEST.$vid up}
		{ip link show \$NIC_TEST.$vid}
		{ip addr show \$NIC_TEST.$vid}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# setup vmvf2

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip link add link \$NIC_TEST name \$NIC_TEST.$vid type vlan id $vid}
		{ip link set \$NIC_TEST.$vid up}
		{ip addr flush \$NIC_TEST.$vid}
		{ip addr add 172.30.${ipaddr_vlan}.21/24 dev \$NIC_TEST.$vid}
		{ip addr add 2021:db8:${ipaddr_vlan}::21/64 dev \$NIC_TEST.$vid}
		{ip link set \$NIC_TEST.$vid up}
		{ip link show \$NIC_TEST.$vid}
		{ip addr show \$NIC_TEST.$vid}
	)
	vmsh cmd_set $vm2 "${cmd[*]}"

	# test
	local result=0
	if ! do_vm_netperf $vm1 172.30.${ipaddr_vlan}.21 2021:db8:${ipaddr_vlan}::21 $result_file; then
		result=1
	fi
	if ! do_vm_netperf $vm2 172.30.${ipaddr_vlan}.11 2021:db8:${ipaddr_vlan}::11 $result_file; then
		result=1
	fi
	if ! do_vm_netperf $vm1 172.30.${ipaddr_vlan}.1 2021:db8:${ipaddr_vlan}::1 $result_file; then
		result=1
	fi
	if ! do_vm_netperf $vm2 172.30.${ipaddr_vlan}.1 2021:db8:${ipaddr_vlan}::1 $result_file; then
		result=1
	fi

	# clearnup
	sriov_detach_vf_from_vm $nic_test 0 1 $vm1
	sriov_detach_vf_from_vm $nic_test 0 2 $vm2

	sriov_remove_vfs $nic_test 0

	sync_set server test_vmvf_vmvf_vlan_end

	return $result
}

sriov_test_vmvf_bond_remote()
{
	log_header "VMVF_BOND <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bond_vmvf_remote_start
		sync_wait client test_vmvf_bond_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_bond_remote_start
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi

		if (( $? != 0 )); then
			sync_set server test_vmvf_bond_remote_end
			return 1
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		echo "test_ifaces:$iface1,$iface2"
		# disable DHCP and NetworkManager on the interface
		cat /etc/sysconfig/network-scripts/ifcfg-${iface1} | \
			sed 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' | \
			sed 's/NM_CONTROLLED=yes/NM_CONTROLLED=no/g' | \
			tee  /etc/sysconfig/network-scripts/ifcfg-${iface1}
		cat /etc/sysconfig/network-scripts/ifcfg-${iface2} | \
			sed 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' | \
			sed 's/NM_CONTROLLED=yes/NM_CONTROLLED=no/g' | \
			tee  /etc/sysconfig/network-scripts/ifcfg-${iface2}

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		if ! sriov_create_vfs ${iface1} 0 2; then
			sync_set server test_vmvf_bond_remote_end
			return 1
		fi

		if ! sriov_create_vfs ${iface2} 0 2; then
			sync_set server test_vmvf_bond_remote_end
			return 1
		fi

		ip link set ${iface1} up
		ip link set ${iface2} up

		ip link set  ${iface1} vf 0 spoofchk off
		ip link set  ${iface2} vf 1 spoofchk off
		ip link set  ${iface1} vf 0 trust on
		ip link set  ${iface2} vf 1 trust on
		ip link show
		ip addr show

		if ! sriov_attach_vf_to_vm ${iface1} 0 1 $vm1 $mac1; then
			result=1
		else
			if ! sriov_attach_vf_to_vm ${iface2} 0 2 $vm1 $mac2; then
				result=1
			else
				local cmd=(
					{export NIC_TEST1=\$\(ip link show \| grep $mac1 -B1 \| sed \'/$mac1/d\' \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST2=\$\(ip link show \| grep $mac2 -B1 \| sed \'/$mac2/d\' \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST1 down}
					{ip link set \$NIC_TEST2 down}
					{modprobe -r bonding}
					{sleep 2}
					{modprobe bonding}
					{sleep 5}
					{echo +bond1 \> /sys/class/net/bonding_masters}
					{cat /sys/class/net/bonding_masters}
					{echo active-backup \> /sys/class/net/bond1/bonding/mode}
					{echo active \> /sys/class/net/bond1/bonding/fail_over_mac}
					{echo 100 \> /sys/class/net/bond1/bonding/miimon}
					{echo +\$NIC_TEST1 \> /sys/class/net/bond1/bonding/slaves}
					{echo +\$NIC_TEST2 \> /sys/class/net/bond1/bonding/slaves}
					{ip link set bond1 up}
					{ip addr flush bond1}
					{ip addr add 172.30.${ipaddr}.11/24 dev bond1}
					{ip addr add 2021:db8:${ipaddr}::11/64 dev bond1}
					{ip link show}
					{ip addr show}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				# NIC_TEST1 and NIC_TEST2 are all up. NIC_TEST1 is active
				if ! do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file; then
					result=1
				fi

				# NIC_TEST1 is down and NIC_TEST2 is active
				local cmd=(
					{export NIC_TEST1=\$\(cat /sys/class/net/bond1/bonding/active_slave\)}
					{ip link set \$NIC_TEST1 down}
					{ip link show}
					{ip addr show}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if ! do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file; then
					result=1
				fi

				# NIC_TEST2 is down and NIC_TEST1 is active
				local cmd=(
					{export NIC_TEST2=\$\(cat /sys/class/net/bond1/bonding/active_slave\)}
					{export NIC_TEST1=\$\(cat /sys/class/net/bond1/bonding/slaves \| sed \"s/\$NIC_TEST2//\" \| sed \'s/ //\'\)}
					{ip link set \$NIC_TEST1 up}
					{ip link set \$NIC_TEST2 down}
					{ip link show}
					{ip addr show}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if ! do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file; then
					result=1
				fi

				# cleanup
				local cmd=(
					{export NIC_TEST1=\$\(ip link show \| grep bond1 \| sed \'/bond1:/d\' \| sed -n 1p \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST2=\$\(ip link show \| grep bond1 \| sed \'/bond1:/d\' \| sed -n 2p \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set bond1 down}
					{echo -\$NIC_TEST1 \> /sys/class/net/bond1/bonding/slaves}
					{echo -\$NIC_TEST2 \> /sys/class/net/bond1/bonding/slaves}
					{echo -bond1 \> /sys/class/net/bonding_masters}
					{modprobe -r bonding}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
			fi

			sriov_detach_vf_from_vm ${iface1} 0 1 $vm1
			sriov_detach_vf_from_vm ${iface2} 0 2 $vm1
		fi

		sriov_remove_vfs ${iface1} 0
		sriov_remove_vfs ${iface2} 0

		sync_set server test_vmvf_bond_remote_end
	fi

	return $result
}

#two vfs from different pfs on one vm
sriov_test_vmvf1vf2_remote()
{
	log_header "sriov_test_vmvf1vf2_remote" $result_file

	local result=0
	local test_name=sriov_test_vmvf1vf2_remote
	local server_ip4="192.100.${ipaddr}.1"
	local vf1_ip4="192.100.${ipaddr}.2"
	local vf2_ip4="192.101.${ipaddr}.2"
	local server_ip6="2021:db08:${ipaddr}:2345::1"
	local vf1_ip6="2021:db08:${ipaddr}:2345::2"
	local vf2_ip6="2021:db09:${ipaddr}:2345::2"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local pf2_ip4="192.101.${ipaddr}.1"

	ip link set $nic_test up

	if i_am_server;then

		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		ip route add 192.101.${ipaddr}.0/${ip4_mask_len} via ${vf1_ip4}
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end
		ip addr flush $nic_test

		return 0
	fi


	sync_wait server ${test_name}_start

	OLD_NIC_NUM=$NIC_NUM
	OLD_NIC_DRIVER=$NIC_DRIVER
	OLD_NIC_MODEL=$NIC_MODEL
	OLD_NIC_SPEED=$NIC_SPEED

	local NIC_NUM=2
	if [[ "${CLIENT_INTERFACES}" != 'None' ]]; then
		local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
	else
		local test_iface="$(get_test_nic ${NIC_NUM})"
	fi

	if [ $? -ne 0 ];then
		echo "$test_name get required_iface failed."
		sync_set server ${test_name}_end
		return 1
	fi
	iface1=$(echo $test_iface | awk '{print $1}')
	iface2=$(echo $test_iface | awk '{print $2}')
	echo "test_ifaces:$iface1,$iface2"
	ip link set $iface1 up
	ip link set $iface2 up
	ip addr flush $iface1
	ip addr flush $iface2
	sleep 1
	ip addr add ${pf2_ip4}/${ip4_mask_len} dev $iface2
	ip route add 192.100.${ipaddr}.0/${ip4_mask_len} via ${vf2_ip4}
	ip addr show $iface2
	ip route
	local vid=3
	local mac1="00:de:a1:$(printf %02x $ipaddr):11:01"
	local mac2="00:de:a1:$(printf %02x $ipaddr):12:01"

	if ! sriov_create_vfs $iface1 0 2 ||
		! sriov_create_vfs $iface2 0 2; then
			echo "${test_name} failed:create vfs failed."
			sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	ip link set $iface1 up
	ip link set $iface2 up

		#ensure netserver is running
		local cmd=(
			{iptables -F}
			{ip6tables -F}
			{systemctl stop firewalld}
			{pkill netserver\; sleep 2\; netserver}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

	# setup vmvf1
	if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1; then
		echo "${test_name} failed:attach vf to vm failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	local cmd=(
		{export NIC_TEST1=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST1 up}
		{ip addr flush \$NIC_TEST1}
		{ip addr add ${vf1_ip4}/${ip4_mask_len} dev \$NIC_TEST1}
		{ip addr add ${vf1_ip6}/${ip6_mask_len} dev \$NIC_TEST1}
		{ip addr show \$NIC_TEST1}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# setup vmvf2
	if ! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2; then
		echo "${test_name} failed:attach vf to vm failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	local cmd=(
		{export NIC_TEST2=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST2 up}
		{ip addr flush \$NIC_TEST2}
		{ip addr add ${vf2_ip4}/${ip4_mask_len} dev \$NIC_TEST2}
		{ip addr add ${vf2_ip6}/${ip6_mask_len} dev \$NIC_TEST2}
		{ip addr show \$NIC_TEST2}
		{sysctl -w net.ipv4.ip_forward=1}
		{sysctl -w net.ipv6.conf.default.forwarding=1}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# test
	if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file; then
		result=1
		echo "do_vm_netperf vm1 remote failed."
	fi

	ping ${server_ip4} -c 5
	[ $? -ne 0 ] && { result=1;echo "ipv4 forward failed"; }

	ip addr flush $iface2

	# clearnup
	sriov_detach_vf_from_vm $iface1 0 1 $vm1
	sriov_detach_vf_from_vm $iface2 0 2 $vm1

	sriov_remove_vfs $iface1 0
	sriov_remove_vfs $iface2 0

	NIC_NUM=$OLD_NIC_NUM
	NIC_DRIVER=$OLD_NIC_DRIVER
	NIC_MODEL=$OLD_NIC_MODEL
	NIC_SPEED=$OLD_NIC_SPEED

	sync_set server ${test_name}_end

	return $result
}
# two VFs on different PF
sriov_test_vmvf1_vmvf2_remote()
{
	log_header "sriov_test_vmvf1_vmvf2_remote" $result_file

	local result=0
	local test_name=sriov_test_vmvf1_vmvf2_remote
	local server_ip4="192.100.${ipaddr}.1"
	local vm1_ip4="192.100.${ipaddr}.2"
	local vm2_ip4="192.100.${ipaddr}.3"
	local server_ip6="2021:db08:${ipaddr}:2345::1"
	local vm1_ip6="2021:db08:${ipaddr}:2345::2"
	local vm2_ip6="2021:db08:${ipaddr}:2345::3"
	local ip4_mask_len=24
	local ip6_mask_len=64

	ip link set $nic_test up

	if i_am_server;then

		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end
		ip addr flush $nic_test

		return 0
	fi


	sync_wait server ${test_name}_start

	OLD_NIC_NUM=$NIC_NUM
	OLD_NIC_DRIVER=$NIC_DRIVER
	OLD_NIC_MODEL=$NIC_MODEL
	OLD_NIC_SPEED=$NIC_SPEED

	local NIC_NUM=2
	if [[ "${CLIENT_INTERFACES}" != 'None' ]]; then
		local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
	else
		local test_iface="$(get_test_nic ${NIC_NUM})"
	fi

	if [ $? -ne 0 ];then
		echo "$test_name get required_iface failed."
		sync_set server ${test_name}_end
		return 1
	fi
	iface1=$(echo $test_iface | awk '{print $1}')
	iface2=$(echo $test_iface | awk '{print $2}')
	echo "test_ifaces:$iface1,$iface2"


	local vid=3
	local mac1="00:de:a1:$(printf %02x $ipaddr):11:01"
	local mac2="00:de:a1:$(printf %02x $ipaddr):12:01"

	if ! sriov_create_vfs $iface1 0 2 ||
		! sriov_create_vfs $iface2 0 2; then
		echo "${test_name} failed:create vfs failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	ip link set $iface1 up
	ip link set $iface2 up
	# The current attach vf operation will restart the vm and put any operations after the vm started.
	if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1; then
		echo "${test_name} failed:attach vf to vm failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	if ! sriov_attach_vf_to_vm $iface2 0 2 $vm2 $mac2; then
		echo "${test_name} failed:attach vf to vm failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	#ensure netserver is running
	local cmd=(
		{iptables -F}
		{ip6tables -F}
		{systemctl stop firewalld}
		{pkill netserver\; sleep 2\; netserver}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"
	vmsh cmd_set $vm2 "${cmd[*]}"

	# setup vmvf1

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip addr add ${vm1_ip4}/${ip4_mask_len} dev \$NIC_TEST}
		{ip addr add ${vm1_ip6}/${ip6_mask_len} dev \$NIC_TEST}
		{ip addr show \$NIC_TEST}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# setup vmvf2

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip addr add ${vm2_ip4}/${ip4_mask_len} dev \$NIC_TEST}
		{ip addr add ${vm2_ip6}/${ip6_mask_len} dev \$NIC_TEST}
		{ip addr show \$NIC_TEST}
	)
	vmsh cmd_set $vm2 "${cmd[*]}"

	# test
	if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file; then
		result=1
		echo "do_vm_netperf vm1 remote failed."
	fi
	if ! do_vm_netperf $vm2 ${server_ip4} ${server_ip6} $result_file; then
		result=1
		echo "do_vm_netperf vm2 remote failed."
	fi
	if ! do_vm_netperf $vm2 ${vm1_ip4} ${vm1_ip6} $result_file; then
		result=1
		echo "do_vm_netperf vm2 vm1 failed."
	fi


	# clearnup
	sriov_detach_vf_from_vm $iface1 0 1 $vm1
	sriov_detach_vf_from_vm $iface2 0 2 $vm2

	sriov_remove_vfs $iface1 0
	sriov_remove_vfs $iface2 0

	NIC_NUM=$OLD_NIC_NUM
	NIC_DRIVER=$OLD_NIC_DRIVER
	NIC_MODEL=$OLD_NIC_MODEL
	NIC_SPEED=$OLD_NIC_SPEED

	sync_set server ${test_name}_end

	return $result
	}

# two VFs on different PF
sriov_test_vmvf1_vmvf2_vlan_remote()
{
	log_header "sriov_test_vmvf1_vmvf2_vlan_remote" $result_file
	local result=0
	local test_name=sriov_test_vmvf1_vmvf2_vlan_remote
	local server_ip4="192.100.${ipaddr}.1"
	local vm1_ip4="192.100.${ipaddr}.2"
	local vm2_ip4="192.100.${ipaddr}.3"
	local server_ip6="2021:db08:${ipaddr}:1234::1"
	local vm1_ip6="2021:db08:${ipaddr}:1234::2"
	local vm2_ip6="2021:db08:${ipaddr}:1234::3"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	ip link set $nic_test up

	if i_am_server;then

		ip link add link $nic_test name ${nic_test}.$vlan_id type vlan id $vlan_id
		ip link set ${nic_test}.$vlan_id up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}.$vlan_id
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}.$vlan_id
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end
		ip link del ${nic_test}.$vlan_id
		ip addr flush $nic_test

		return 0
	fi


	sync_wait server ${test_name}_start

	OLD_NIC_NUM=$NIC_NUM
	OLD_NIC_DRIVER=$NIC_DRIVER
	OLD_NIC_MODEL=$NIC_MODEL
	OLD_NIC_SPEED=$NIC_SPEED

	local NIC_NUM=2
	if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
		local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
	else
		local test_iface="$(get_test_nic ${NIC_NUM})"
	fi

	if [ $? -ne 0 ];then
		echo "$test_name get required_iface failed."
		sync_set server ${test_name}_end
		return 1
	fi
	iface1=$(echo $test_iface | awk '{print $1}')
	iface2=$(echo $test_iface | awk '{print $2}')
	echo "test_ifaces:$iface1,$iface2"


	local vid=3
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"

	if ! sriov_create_vfs $iface1 0 2 ||
		! sriov_create_vfs $iface2 0 2; then
		echo "${test_name} failed:create vfs failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	ip link set $iface1 up
	ip link set $iface2 up

	# The current attach vf operation will restart the vm and put any operations after the vm started.
	if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1; then
		echo "${test_name} failed:attach vf to vm failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	if ! sriov_attach_vf_to_vm $iface2 0 2 $vm2 $mac2; then
		echo "${test_name} failed:attach vf to vm failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	#ensure netserver is running
	local cmd=(
		{iptables -F}
		{ip6tables -F}
		{systemctl stop firewalld}
		{pkill netserver\; sleep 2\; netserver}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"
	vmsh cmd_set $vm2 "${cmd[*]}"

	# setup vmvf1

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip link add link \$NIC_TEST name \$NIC_TEST\.${vlan_id} type vlan id $vlan_id}
		{ip link set \$NIC_TEST\.${vlan_id} up}
		{ip addr add ${vm1_ip4}/${ip4_mask_len} dev \$NIC_TEST\.${vlan_id}}
		{ip addr add ${vm1_ip6}/${ip6_mask_len} dev \$NIC_TEST\.${vlan_id}}
		{ip addr show \$NIC_TEST\.${vlan_id}}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# setup vmvf2

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip link add link \$NIC_TEST name \$NIC_TEST\.${vlan_id} type vlan id $vlan_id}
		{ip link set \$NIC_TEST\.${vlan_id} up}
		{ip addr add ${vm2_ip4}/${ip4_mask_len} dev \$NIC_TEST\.${vlan_id}}
		{ip addr add ${vm2_ip6}/${ip6_mask_len} dev \$NIC_TEST\.${vlan_id}}
		{ip addr show \$NIC_TEST\.${vlan_id}}
	)
	vmsh cmd_set $vm2 "${cmd[*]}"

	# test
	if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file; then
		result=1
		echo "do_vm_netperf vm1 remote failed."
	fi
	if ! do_vm_netperf $vm2 ${server_ip4} ${server_ip6} $result_file; then
		result=1
		echo "do_vm_netperf vm2 remote failed."
	fi
	if ! do_vm_netperf $vm2 ${vm1_ip4} ${vm1_ip6} $result_file; then
		result=1
		echo "do_vm_netperf vm2 vm1 failed."
	fi


	# clearnup
	sriov_detach_vf_from_vm $iface1 0 1 $vm1
	sriov_detach_vf_from_vm $iface2 0 2 $vm2

	sriov_remove_vfs $iface1 0
	sriov_remove_vfs $iface2 0

	NIC_NUM=$OLD_NIC_NUM
	NIC_DRIVER=$OLD_NIC_DRIVER
	NIC_MODEL=$OLD_NIC_MODEL
	NIC_SPEED=$OLD_NIC_SPEED

	sync_set server ${test_name}_end

	return $result
}

# create max supported VFs, attach to two different VMs
sriov_test_max_vfs()
{
	# due to https://bugzilla.redhat.com/show_bug.cgi?id=2001525,the max vf which guest can added is 13
	# Fixed by qemu 6.2.0 rebase
	log_header "sriov_test_max_vfs" $result_file

	local result=0
	local test_name="sriov_test_max_vfs"
	local server_ip4="192.100.${ipaddr}.254"
	local vm_ip4_perfix="192.100.${ipaddr}."
	local server_ip6="2021:db08:${ipaddr}::254"
	local vm_ip6_perfix="2021:db08:${ipaddr}::"
	local ip4_mask_len=24
	local ip6_mask_len=64

	ip link set $nic_test up

	if i_am_server;then
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end 14400
		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_start
		#local driver=$(ethtool -i ${nic_test} | grep "driver" | awk '{print $NF}')
		#local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local total_vfs=$(sriov_get_max_vf_from_pf $nic_test 0)

		if ! sriov_create_vfs $nic_test 0 $total_vfs;then
			let result++
			rlFail "${test_name} failed: create vfs failed."
		else
			local vm1_mac_perfix="00:de:ad:$(printf %02x $ipaddr):01:"
			local vm2_mac_perfix="00:de:ad:$(printf %02x $ipaddr):02:"
			local vm1_attach_vf_num=$((total_vfs/2))
			local vm2_attach_vf_num=$((total_vfs-vm1_attach_vf_num))
			# reduce vf num because PCI slots is limit
			[ $vm1_attach_vf_num -gt 20 ] && vm1_attach_vf_num=9
			[ $vm2_attach_vf_num -gt 20 ] && vm2_attach_vf_num=9
			if [ "$SYS_ARCH" == "aarch" ];then
				[ $vm1_attach_vf_num -gt 8 ] && vm1_attach_vf_num=8
				[ $vm2_attach_vf_num -gt 8 ] && vm2_attach_vf_num=8
			fi
			sleep 30

			for((i=1;i<=$vm1_attach_vf_num;i++))
			do
				local vf_mac="${vm1_mac_perfix}$(printf %02x $i)"
				if ! sriov_attach_vf_to_vm $nic_test 0 $i $vm1 ${vf_mac};then
					let result++
					rlLog "${test_name} failed: can't attach vf $i to vm1."
				else
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip link set \$NIC_TEST up}
						{ip addr add ${vm_ip4_perfix}${i}/${ip4_mask_len} dev \$NIC_TEST}
						{ip addr add ${vm_ip6_perfix}${i}/${ip6_mask_len} dev \$NIC_TEST}
						{ip a}
						{timeout 60s bash -c \"until ping -c1 ${server_ip4}\; do sleep 5\; done\"}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					if [ $? -ne 0 ];then
						let result++
						rlFail "ping failed via vm1 vf $i"
					fi
					#if [ $i -eq $vm1_attach_vf_nums ];then
					#	if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file; then
					#			let result++
					#	fi
					#fi
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					sriov_detach_vf_from_vm $nic_test 0 $i $vm1
				fi
			done
			for((i=$((vm1_attach_vf_num+1));i<=$((vm1_attach_vf_num+vm2_attach_vf_num));i++))
				do
					local vf_mac="${vm2_mac_perfix}$(printf %02x $i)"
					if ! sriov_attach_vf_to_vm $nic_test 0 $i $vm2 ${vf_mac};then
						let result++
						rlLog "${test_name} failed: can't attach vf $i to vm2."
					else
						local cmd=(
							{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
							{ip link set \$NIC_TEST up}
							{ip addr add ${vm_ip4_perfix}${i}/${ip4_mask_len} dev \$NIC_TEST}
							{ip addr add ${vm_ip6_perfix}${i}/${ip6_mask_len} dev \$NIC_TEST}
							{ip a}
							{timeout 60s bash -c \"until ping -c1 ${server_ip4}\; do sleep 5\; done\"}
						)
						vmsh cmd_set $vm2 "${cmd[*]}"
						if [ $? -ne 0 ];then
							let result++
							rlFail "ping failed via vm2 vf $i"
						fi
						#if [ $i -eq $total_vfs ];then
						#		if ! do_vm_netperf $vm2 ${server_ip4} ${server_ip6} $result_file; then
						#				let result++
						#		fi
						#fi
						local cmd=(
							{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
							{ip addr flush \$NIC_TEST}
						)
						vmsh cmd_set $vm2 "${cmd[*]}"
						sriov_detach_vf_from_vm $nic_test 0 $i $vm2
					fi
				done

				for((i=1;i<=$vm1_attach_vf_num;i++))
				do
					sriov_detach_vf_from_vm $nic_test 0 $i $vm1
				done
				for((i=$((vm1_attach_vf_num+1));i<=$((vm1_attach_vf_num+vm2_attach_vf_num));i++))
				do
					sriov_detach_vf_from_vm $nic_test 0 $i $vm2
				done
				sriov_remove_vfs $nic_test 0
		fi
		#sometimes vm will panic. make sure they are start here.
		virsh list | grep $vm1 || virsh start $vm1
		virsh list | grep $vm2 || virsh start $vm2
		sleep 15
		sync_set server ${test_name}_end 14400
	fi

	return $result
}

# create max supported count VFs, attach each one to different VMs
sriov_test_max_vfs_attaching_to_different_vms()
{
	log_header "sriov_test_max_vfs_attaching_to_different_vms" $result_file

	local result=0
	local test_name="sriov_test_max_vfs_attaching_to_different_vms"
	local server_ip4="192.100.${ipaddr}.250"
	local vm_ip4_perfix="192.100.${ipaddr}."
	local server_ip6="2021:db08:${ipaddr}::250"
	local vm_ip6_perfix="2021:db08:${ipaddr}::"
	local ip4_mask_len=24
	local ip6_mask_len=64

	ip link set $nic_test up

	if i_am_server;then

		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end 14400
		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_start
		#local driver=$(ethtool -i ${nic_test} | grep "driver" | awk '{print $NF}')
				#local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local total_vfs=$(sriov_get_max_vf_from_pf ${nic_test})
		rlLog "total_vfs $total_vfs"

		if ! sriov_create_vfs $nic_test 0 $total_vfs;then
			let result++
			rlFail "${test_name} failed: create vfs failed."

		else
			# prepare VMs

				# define default vnet
			if ! virsh net-list | grep default &&
				! virsh net-start default;then
				virsh net-define /usr/share/libvirt/networks/default.xml
				virsh net-start default
				virsh net-autostart default
			fi
			#ip link show | grep virbr0 || ip link add name virbr0 type bridge
			#ip link set virbr0 up
			ip link show | grep virbr1 || ip link add name virbr1 type bridge
			ip link set virbr1 up

			rlLog "Download guest image..."
			mkdir -p /home/maxvfstest/images
			pushd "/home/maxvfstest/images/" 1>/dev/null
			[ -e $(basename $IMG_GUEST) ] || wget -nv -N $IMG_GUEST
			chmod -R 777 /home/maxvfstest/images/$(basename $IMG_GUEST)
			if [ "$SYS_ARCH" == "aarch" ];then
				[ -z "$IMG_FD" ] && IMG_FD=`echo $IMG_GUEST | sed 's/.qcow2/_VARS.fd/g'`
				[ -e $(basename $IMG_FD) ] || wget -nv -N $IMG_FD
				chmod -R 777 /home/maxvfstest/images/$(basename $IMG_FD)
			fi

			local vmname_perfix="testvm"
			local vm_mac_perfix="00:de:aa:$(printf %02x $ipaddr):01:"

			local vm_num=8
			[ $total_vfs -lt $vm_num ] && vm_num=$total_vfs

			#install VMs
			for((i=1;i<=$vm_num;i++))
			do
				local vmname=${vmname_perfix}$i

				if virsh list | grep "$vmname " ||
					virsh start $vmname;then
					continue
				fi

				cp --remove-destination $(basename $IMG_GUEST) ${vmname}.qcow2
				cp --remove-destination $(basename $IMG_FD) ${vmname}.fd
				if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
					virt-copy-in -a ${vmname}.qcow2 ${CASE_PATH}/../../common/tools/brewkoji_install.sh /root
				fi
				rlLog "Creating guest $vmname..."
				if [ "$SYS_ARCH" == "aarch" ];then
					pci_str=$(for i in `seq 1 15`;do echo -n "--controller type=pci,index=$i,model=pcie-root-port ";done)
					virt-install \
						--name $vmname \
						--vcpus=1 \
						--ram=1024 \
						--disk path=/home/maxvfstest/images/${vmname}.qcow2,device=disk,bus=virtio,format=qcow2 \
						--network bridge=virbr0,model=virtio,mac=${vm_mac_perfix}$(printf %02x $i) \
						--accelerate \
						--graphics vnc,listen=0.0.0.0 \
						--force \
						--os-variant=rhel-unknown \
						--noautoconsol \
						--boot loader=/usr/share/AAVMF/AAVMF_CODE.fd,loader_ro=yes,loader_type=pflash,nvram=/var/lib/libvirt/images/${vmname}.fd,loader_secure=no \
						--controller type=pci,index=0,model=pcie-root  \
						$pci_str
				else
					#pci_str=$(for i in `seq 1 15`;do echo -n "--controller type=pci,index=$i,model=pcie-root-port ";done)
					virt-install \
						--name $vmname \
						--vcpus=1 \
						--ram=1024 \
						--disk path=/home/maxvfstest/images/${vmname}.qcow2,device=disk,bus=virtio,format=qcow2 \
						--network bridge=virbr0,model=virtio,mac=${vm_mac_perfix}$(printf %02x $i) \
						--boot hd \
						--accelerate \
						--graphics vnc,listen=0.0.0.0 \
						--force \
						--os-variant=rhel-unknown \
						--noautoconsole
						#--controller type=pci,index=0,model=pcie-root  \
						#$pci_str
				fi

				# wait VM bootup
				sleep 90

				# update VM kernel to the same one as host
				sriov_config_vm_repo $vmname
#				local k="yum install -y $RPM_KERNEL $RPM_KERNEL_CORE $RPM_KERNEL_MODULES $RPM_KERNEL_MODULES_INTERNAL"
#				vmsh run_cmd $vmname "$k"
#				virsh reboot $vmname
#				sleep 120


				# vm setup
				local cmd=(
					{iptables -F}
					{ip6tables -F}
					{systemctl stop firewalld}
					{setenforce 0}
					{yum install -y bzip2}
					{yum install -y wget}
					{yum install -y kernel-kernel-networking-vnic-sriov}
					{yum install -y automake gcc make}
					{source /mnt/tests/kernel/networking/common/install.sh}
					{netperf_install}
					{pkill netserver\; sleep 2\; netserver}
					# work around bz883695
					{lsmod \| grep mlx4_en \|\| modprobe mlx4_en}
					{tshark -v \&\>/dev/null \|\| yum -y install wireshark}
				)
				if (($rhel_version >= 7)); then
					vmsh run_cmd $vmname "systemctl stop NetworkManager"
				fi
				vmsh cmd_set $vmname "${cmd[*]}"
				#clean the images
				rm -f ${vmname}.qcow2
				rm -f ${vmname}.fd
			done

			ls
			popd 1>/dev/null

			sleep 30

			vm_mac_perfix="00:de:ad:$(printf %02x $ipaddr):01:"

			#vm_num=$(virsh list | grep "testvm" | wc -l)

			let vfs_p=$total_vfs/$vm_num
			rlLog "vfs num on each vm $vfs_p"

			for ((i=1;i<=$vm_num;i++))
			do
				vmname=${vmname_perfix}$i
				let m=$i-1
				let j=$m*${vfs_p}+1
				let k=$i*${vfs_p}
				for((j=($i-1)*${vfs_p}+1;j<=$k;j++))
				do
					local vf_mac="${vm_mac_perfix}$(printf %02x $j)"
					if ! sriov_attach_vf_to_vm $nic_test 0 $j $vmname ${vf_mac};then
						let result++
						rlFail "${test_name} failed: can't attach vf $j to $vmname."
					else
						local cmd=(
							{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
							{ip link set \$NIC_TEST up}
							{ip addr add ${vm_ip4_perfix}${j}/${ip4_mask_len} dev \$NIC_TEST}
							{ip addr add ${vm_ip6_perfix}${j}/${ip6_mask_len} dev \$NIC_TEST}
							{sleep 5}
							{ping ${server_ip4} -c3}
						)
						vmsh cmd_set $vmname "${cmd[*]}"
						if [ $? -ne 0 ];then
							let result++
							rlFail "ping failed via $vmname vf $j"
						else
							local cmd=(
								{netperf -H ${server_ip4} -l 10 -- -k "THROUGHPUT" \> perf$j \&}
								{sleep 15}
								{export PERF=\$\(cat perf$j \| grep \"THROUGHPUT\" \| awk -F\"=\" \'\{print \$2\}\'\)}
								{\[ -n \"\$PERF\" \] \|\| export PERF=0}
								{\(\(\$\(bc \<\<\< \"\$PERF \> 100\"\)\)\) \|\| \{ echo \"$vmname vf$j perf too low\"\;cat trigger_error\; \} }
							)
							vmsh cmd_set $vmname "${cmd[*]}"
							if [ $? -ne 0 ];then
								rlFail "${vmname} throughput lower than 100"
								let result++
							fi
						fi
					fi
				done
			done

			sleep 130

			for((i=1;i<=$vm_num;i++))
			do
				vmname=${vmname_perfix}$i
#				let k=$i*$vfs_p
#				for((j=($i-1)*$vfs_p+1;j<=$k;j++))
#				do
#					local cmd=(
#						{export PERF=\$\(cat perf$j \| grep \"THROUGHPUT\" \| awk -F\"=\" \'\{print \$2\}\'\)}
#						{\[ -n \"\$PERF\" \] \|\| export PERF=0}
#						{echo \"$vmname PERF=\$PERF\"}
#						{\(\(\$\(bc \<\<\< \"\$PERF \> 100\"\)\)\) \|\| \{ echo \"$vmname vf$j perf too low\"\;cat trigger_error\; \} }
#					)
#					vmsh cmd_set $vmname "${cmd[*]}"
#					if [ $? -ne 0 ];then
#						rlFail "${vmname} throughput lower than 100"
#						let result++
#					fi
#					sriov_detach_vf_from_vm $nic_test 0 $j $vmname
#				done
				rlLog "clean test image and guest"
				virsh destroy $vmname
				virsh undefine $vmname

			done

			sriov_remove_vfs $nic_test 0
		fi
		sync_set server ${test_name}_end 14400
	fi

	return $result
}

#32 vfs
sriov_test_bz1701191()
{
	log_header "sriov_test_bz1701191" $result_file
	local result=0
	ip link set $nic_test up
	if i_am_server;then
		sync_set client test_bz1701191_start
		sync_wait client test_bz1701191_end
	fi
	if i_am_client;then
		#if [ "$NIC_DRIVER" = "i40e" ];then
		sync_wait server test_bz1701191_start
		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1701191_end
			return 1
		fi
		pf_bus_info=$(ethtool -i $nic_test | grep 'bus-info'| sed 's/bus-info: //')
		vf_bus_info=$(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///' | sed -n ${iVF}p)
		vf_nodedev=pci_$(echo $vf_bus_info | sed 's/[:|.]/_/g')
		pf_nodedev=pci_$(echo $pf_bus_info | sed 's/[:|.]/_/g')
		vf_domain=$(echo $vf_bus_info | awk -F '[:|.]' '{print $1}')
		vf_bus=$(echo $vf_bus_info | awk -F '[:|.]' '{print $2}')
		vf_slot=$(echo $vf_bus_info | awk -F '[:|.]' '{print $3}')
		vf_function=$(echo $vf_bus_info | awk -F '[:|.]' '{print $4}')
		cat <<-EOF > ${vf_nodedev}.xml
			<interface type="hostdev" managed="no">
				<source>
					<address type='pci' domain='0x${vf_domain}' bus='0x${vf_bus}' slot='0x${vf_slot}' function='0x${vf_function}'/>
				</source>
				<mac address="00:1a:4a:16:20:81"/>
			</interface>
		EOF
		if virsh nodedev-detach $vf_nodedev && virsh attach-device $vm1 ${vf_nodedev}.xml;then
			result=0
			if [[ $ENABLE_RT_KERNEL != "yes" ]]; then
				virsh detach-device $vm1 ${vf_nodedev}.xml
			else
				local rhel_version=$( cat /etc/redhat-release | sed  's/\(.*\)\([0-9].[0-9]\)\(.*\)/\2/g')
				if [[ $(echo "${rhel_version} <= 8.6" | bc) -eq 1 ]]; then
					virsh detach-device $vm1 ${vf_nodedev}.xml
					virsh shutdown $vm1
					sleep 10
					virsh start $vm1
					sleep 10
					local vm_status=$(virsh list --all | grep $vm1 |  awk '{print $3,$4}')
					rlLog "$vm in $vm_status status"
				else
					virsh detach-device $vm1 ${vf_nodedev}.xml
				fi
			fi
			rlRun "virsh nodedev-reattach  $vf_nodedev"
		else
			rlLog "failed to attach VF to VM with managed=no"
			result=1
		fi
		rlLog "repeoducer for bz1931779: binding the PF(with a VF) driver to vfio-pci "
		rlRun "virsh nodedev-detach $pf_nodedev"
		#add more time to reproduce bug https://bugzilla.redhat.com/show_bug.cgi?id=2016618
		sleep 120
		rlRun "virsh nodedev-list | grep $pf_nodedev" "0-999"
		rlRun "virsh nodedev-reattach  $pf_nodedev" || rlRun "virsh nodedev-reset $pf_nodedev"
		rlRun "virsh nodedev-reattach  $pf_nodedev"
		sriov_remove_vfs $nic_test 0
		sync_set server test_bz1701191_end
		return $result
		#else
			#sync_wait server test_bz1701191_start
			#sync_set server test_bz1701191_end
			#echo "skip test"
		#fi
	fi
}

sriov_test_bz1392128()
{
	log_header "sriov_test_bz1392128" $result_file

	local result=0
	local test_name="sriov_test_bz1392128"
	local server_ip4="192.100.${ipaddr}.1"
	local vm1_ip4="192.100.${ipaddr}.2"
	local vm2_ip4="192.100.${ipaddr}.3"
	local server_ip6="2021:db08:${ipaddr}::1"
	local vm1_ip6="2021:db08:${ipaddr}::2"
	local vm2_ip6="2021:db08:${ipaddr}::3"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local count_vm1=0
	local count_vm2=0

	ip link set $nic_test up

	if i_am_server;then

		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		ip addr show $nic_test
		sync_set client ${test_name}_start 10800
		sync_wait client ${test_name}_end
		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_start
		#local driver=$(ethtool -i ${nic_test} | grep "driver" | awk '{print $NF}')
		#local driver=$(ethtool -i $PF | grep 'driver' | sed 's/driver: //')
		local total_vfs=$(sriov_get_max_vf_from_pf $nic_test 0)
		if [ $total_vfs -ge 32 ];then
			total_vfs=32
		else
			sync_set server ${test_name}_end 10800
			return 0
		fi

		if ! sriov_create_vfs $nic_test 0 $total_vfs;then
			let result++
			rlFail "${test_name} failed: create vfs failed."

		else
			local vm1_mac_perfix="00:de:ad:$(printf %02x $ipaddr):01:"
			local vm2_mac_perfix="00:de:ad:$(printf %02x $ipaddr):02:"

			local vm1_attach_vf_nums=$((total_vfs/2))

			sleep 30

			for((i=1;i<=$vm1_attach_vf_nums;i++))
			do
				local vf_mac="${vm1_mac_perfix}$(printf %02x $i)"
				if ! sriov_attach_vf_to_vm $nic_test 0 $i $vm1 ${vf_mac};then
					let result++
					rlFail "${test_name} failed: can't attach vf $i to vm1."
				else
					let count_vm1++
					rlLog "vm1 attach vf $count_vm1 times"
					rlLog "`virsh list`"
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip link set \$NIC_TEST up}
						{ip addr add ${vm1_ip4}/${ip4_mask_len} dev \$NIC_TEST}
						{ip addr add ${vm1_ip6}/${ip6_mask_len} dev \$NIC_TEST}
						{ip a}
						{ping ${server_ip4} -c3}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"

					if [ $? -ne 0 ];then
						let result++
						rlFail "ping failed via vm1 vf $i"
					fi
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip a}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
						sriov_detach_vf_from_vm $nic_test 0 $i $vm1
				fi
			done
			for((i=$((vm1_attach_vf_nums+1));i<=$total_vfs;i++))
			do
				local vf_mac="${vm2_mac_perfix}$(printf %02x $i)"
				if ! sriov_attach_vf_to_vm $nic_test 0 $i $vm2 ${vf_mac};then
					let result++
					rlFail "${test_name} failed: can't attach vf $i to vm2."
				else
					let count_vm2++
					rlLog "vm2 attach vf $count_vm2 times"
					rlLog "`virsh list`"
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip link set \$NIC_TEST up}
						{ip addr add ${vm2_ip4}/${ip4_mask_len} dev \$NIC_TEST}
						{ip addr add ${vm2_ip6}/${ip6_mask_len} dev \$NIC_TEST}
						{ip a}
						{ping ${server_ip4} -c3}
					)
					vmsh cmd_set $vm2 "${cmd[*]}"
					if [ $? -ne 0 ];then
						let result++
						rlFail "ping failed via vm2 vf $i"
					fi
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr flush \$NIC_TEST}
						{ip a}
					)
					vmsh cmd_set $vm2 "${cmd[*]}"
					sriov_detach_vf_from_vm $nic_test 0 $i $vm2
				fi
			done


			#for((i=1;i<=$vm1_attach_vf_nums;i++))
			#do
			#	sriov_detach_vf_from_vm $nic_test 0 $i $vm1
			#done
			#for((i=$((vm1_attach_vf_nums+1));i<=$total_vfs;i++))
			#do
			#	sriov_detach_vf_from_vm $nic_test 0 $i $vm2
			#done
			sriov_remove_vfs $nic_test 0
		fi
		sync_set server ${test_name}_end
	fi

	return $result
}

#create remove vfs 20 times
sriov_test_bz1212361()
{
	log_header "Regresssion: bz1212361" $result_file

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1212361_start
		sync_wait client test_bz1212361_end

		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_bz1212361_start

	local cx=0
	while (( $cx < 20 )); do
		sriov_create_vfs $nic_test 0 2 || { sync_set server test_bz1212361_end; return 1; }
		sleep 5
		sriov_remove_vfs $nic_test 0 || { sync_set server test_bz1212361_end; return 1; }

		let cx=cx+1
	done

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_bz1212361_end
		return 1
	fi

	local vf=$(sriov_get_vf_iface $nic_test 0 1)
	if [ -z "$vf" ]; then
		rlFail "FAIL to get VF interface"
		result=1
	else
		ethtool -i $vf

		if sriov_vfmac_is_zero $nic_test 0 1; then
			ip link set $nic_test vf 0 mac 00:de:ad:$(printf %02x $ipaddr):01:01
		fi
		ip link set $vf down
		sleep 2
		ip link set $vf up
		sleep 5
		ip addr flush $vf
		ip addr add 172.30.${ipaddr}.1/24 dev $vf
		ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
		ip -d link show $vf
		ip -d addr show $vf

		do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
		local result=$?

		ip addr flush $vf
	fi

	sriov_remove_vfs $nic_test 0 || { sync_set server test_bz1212361_end; return 1; }

	sync_set server test_bz1212361_end

	return $result
}

#mtu 9000
sriov_test_bz1145063()
{
	log_header "Regresssion: bz1145063" $result_file

	local result=0

	if i_am_server; then
		ip link set $nic_test up
		ip link set mtu 9000 dev $nic_test

		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1145063_start
		sync_wait client test_bz1145063_end

		ip link set mtu 1500 dev $nic_test
		ip addr flush $nic_test

		return 0
	fi

	sync_wait server test_bz1145063_start

	local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_bz1145063_end
		return 1
	fi

	if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
		sriov_remove_vfs $nic_test 0
		sync_set server test_bz1145063_end
		return 1
	fi

	ip link set mtu 9000 dev $nic_test

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip link set mtu 9000 \$NIC_TEST}
		{sleep 5}
		{ip addr flush \$NIC_TEST}
		{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
		{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
	result=$?

	sriov_detach_vf_from_vm $nic_test 0 1 $vm1

	sriov_remove_vfs $nic_test 0

	ip link set mtu 1500 dev $nic_test

	sync_set server test_bz1145063_end

	return $result
}


#config space
# bz1156061 also
sriov_test_bz1205903()
{
	log_header "Regresssion: bz1205903" $result_file

	local result=0

	if i_am_server; then

		sync_set client test_bz1205903
		sync_wait client test_bz1205903

		return 0
	fi

	sync_wait server test_bz1205903

	if ! sriov_create_vfs $nic_test 0 2; then
		sync_set server test_bz1205903
		return 1
	fi

	ip link set $nic_test up

	local vf0_bus_info=$(sriov_get_vf_bus_info $nic_test 0 1)
	local vf0_pci_bus_info="pci_$(echo $vf0_bus_info | sed 's/[:|\.]/_/g')"
	virsh nodedev-detach ${vf0_pci_bus_info}

	local PREV=$(mktemp)
	local CUR=$(mktemp)

	local d1=$(date +"%s")
	lspci -xxx -s ${vf0_bus_info} > $PREV
	cat $PREV
	while (true); do
		lspci -xxx -s $vf0_bus_info > $CUR
		if ! diff -q $PREV $CUR > /dev/null; then
			diff -U 0 $PREV $CUR
			cp $CUR $PREV
			result=1
		fi
		local d2=$(date +"%s");
		if (( $d2 - $d1 > 300 )); then
			break
		fi
	done

	sriov_remove_vfs $nic_test 0

	sync_set server test_bz1205903

	return $result
}

sriov_test_bz1794812_excessive_interrupts()
{
	log_header "excessive interrupts in hypervisor due to get link settings" $result_file

	local result=0

	if i_am_server; then

		sync_set client test_bz1794812
		sync_wait client test_bz1794812

		return 0
	fi
	if i_am_client;then
		if [ "$NIC_DRIVER" = "ixgbe" ];then
			sync_wait server test_bz1794812
			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_bz1794812
				return 1
			fi
			#get the cpu core num
			cpu_cores=$(cat /proc/cpuinfo |grep "processor"|wc -l)
			#get interrupt
			get_interrupts()
			{
				local $1
				let num_c=cpu_cores+1
				for i in `seq 2 $num_c`
				do
					interruputs_pf=$(grep $nic_test /proc/interrupts|grep -v "TxRx"|awk '{print $'$i'}')
					[ ! -z "$interruputs_pf" ] && let interruputs_sum_pf+=$interruputs_pf
					echo $interruputs_sum_pf > interruputs_sum_pf_$1.log
				done
					echo interruputs_sum_pf_$1
					cat interruputs_sum_pf_$1.log
			}
			check_interrupts_increase()
			{
				after=$(cat interruputs_sum_pf_after.log)
				before=$(cat interruputs_sum_pf_before.log)
				let interrupts_increase=after-before
				rlAssertGreaterOrEqual "500 >= $interrupts_increase ?" 500 $interrupts_increase
			}
			run_ethtool()
			{
				local $1
				for i in `seq 0 1000`
				do
					ethtool $1
				done
			}

			ip link set $nic_test up
			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			if [ -z "$vf" ]; then
				rlFail "FAIL to get VF interface"
				result=1
			else
				rlLog "get pf interrupts before running ethtool in loop"
				get_interrupts before
				rlLog "run ethtool in loop"
				run_ethtool $vf > /dev/null
				rlLog "get pf interrupts after running ethtool in loop"
				get_interrupts after
				rlLog "check interrupts increase"
				check_interrupts_increase
			fi
			sriov_remove_vfs $nic_test 0
			sync_set server test_bz1794812
			return $result
		else
			sync_wait server test_bz1794812
			sync_set server test_bz1794812
		fi
	fi
}

#reproducer for bz2041318
sriov_test_vf_trust_broadcast()
{
	$dbg_flag
	log_header "VF <---> REMOTE" $result_file

	local result=0
	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test

		sync_set client test_vf_trust_start
		sync_wait client test_vf_trust_ready_send_packet
		local pkt="Ether(src='00:01:02:03:04:05', dst='ff:ff:ff:ff:ff:ff')/Dot1Q(vlan=32)/ARP(hwsrc='00:01:02:03:04:05' , pdst='1.2.3.4')"
		if [ $(GetDistroRelease) = 8 ];then
			/usr/libexec/platform-python -c  "from scapy.all import *; sendp($pkt, iface='$nic_test', count=10 )"
		else
			python -c  "from scapy.all import *; sendp($pkt, iface='$nic_test', count=10 )"
		fi
		sync_set client test_vf_trust_ready_send_packet
		sync_wait client test_vf_trust_end

		ip addr flush $nic_test
	else
		sync_wait server test_vf_remote_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_trust_ready_send_packet
			sync_wait server test_vf_trust_ready_send_packet
			sync_set server test_vf_trust_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			echo "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf
			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
				#workaround for ionic bz1914175
				ip link set dev $vf address 00:de:ad:$(printf "%02x" $ipaddr):01:01
				ip link set $vf down
				sleep 2
			fi
			ip link set $vf up
			sleep 5
			ip link set $nic_test vf 0 trust on spoof off
			ip link show $nic_test
			ip addr flush $vf
			ip addr add 172.30.${ipaddr}.11/24 dev $vf
			ip addr show $vf
			ping -c5 172.30.${ipaddr}.2
			#check the broadcast with trust off spoof on
			rlRun "tcpdump -i $vf -e vlan and arp -w vlan_broadcast.pcap &"
			rlRun "tcpdump -i $nic_test -e vlan and arp -w pf_vlan_broadcast.pcap &"
			sync_set server test_vf_trust_ready_send_packet
			sync_wait server test_vf_trust_ready_send_packet
			pkill tcpdump
			sleep 5
			rlLog "check the vf whether receive the broadcast"
			tcpdump -r vlan_broadcast.pcap -enn | grep -i 'vlan 32'
			local result=$?
			rlLog "check the pf whether receive the broadcast"
			tcpdump -r pf_vlan_broadcast.pcap -enn | grep -i 'vlan 32'

		fi
		sriov_remove_vfs $nic_test 0
		rm *_broadcast.pcap

		sync_set server test_vf_remote_end
	fi

	return $result
}

# steps from https://bugzilla.redhat.com/show_bug.cgi?id=1302101#c12
sriov_test_trusted_vf_allmulticast()
{
	log_header "VMVF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	testname=trusted_vf_allmulticast

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		ping 225.1.2.3 -I $nic_test &
		sync_set client ${testname}_start
		sync_wait client ${testname}_end

		pkill ping
		ip addr flush $nic_test
	else
		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
		sync_wait server ${testname}_start
		if [[ "$NIC_DRIVER" == "i40e" ]] || [[ "$NIC_DRIVER" == "ice" ]];then
			ethtool --set-priv-flags $nic_test vf-true-promisc-support on
			ethtool --show-priv-flags $nic_test
		fi
		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set ${testname}_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

		fi
		#### Test 1
		rlLog "Test1: PF(host) allmulticast off; VF(guest) allmulticast off; VF trust off"
		ip link show $nic_test

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{timeout 15s bash -c \"tcpdump -i \${NIC_TEST} -c1 host 225.1.2.3 -p\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		(( $? )) || rlFail "Test1 failed, can capture multicast package from guest"

		#### Test 2
		rlLog "Test2: PF(host) allmulticast on; VF(guest) allmulticast on; VF trust off"
		ip link set $nic_test allmulticast on
		ifconfig $nic_test | grep -e "ALLMULTI" || { ((result += 1)); rlFail 'configure allmulticast failed!'; }
		ip link show $nic_test
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST allmulticast on}
			{ip link show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{timeout 15s bash -c \"tcpdump -i \${NIC_TEST} -c1 host 225.1.2.3 -p\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		(( $? )) || rlFail "Test 2 failed, can capture multicast package from guest"

		##### Test 3
		#need detach/attach vf if the vf trust mode is changed
		sriov_detach_vf_from_vm $nic_test 0 1 $vm1

		rlLog "Test3: PF(host) allmulticast on; VF(guest) allmulticast off; VF trust on"
		ip link set $nic_test vf 0 trust on
		ip link show $nic_test | grep -e "vf 0" | grep -e "trust on" || { ((result += 1)); rlFail 'VF trust may not be supported!'; }
		ip link set $nic_test allmulticast on
		ip link show $nic_test
		ifconfig $nic_test | grep -e "ALLMULTI" || { ((result += 1)); rlFail 'configure allmulticast failed!'; }

		sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip link show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{timeout 15s bash -c \"tcpdump -i \${NIC_TEST} -c1 host 225.1.2.3 -p\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		(( $? )) || rlFail "Test3 failed, can capture multicast package from guest"


		##### Test 4
		rlLog "Test4: PF(host) allmulticast off; VF(guest) allmulticast on; VF trust on"
		ip link set $nic_test allmulticast off
		ip link show $nic_test | grep -e "vf 0" | grep -e "trust on" || { ((result += 1)); rlFail 'VF trust may not be supported!'; }
		ip link show $nic_test

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST allmulticast on}
			{ip link show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{timeout 15s bash -c \"tcpdump -i \${NIC_TEST} -c1 host 225.1.2.3 -p\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		(( $? )) && rlFail "Test4 failed, can't capture multicast package from guest"

		##### Test 5
		rlLog "Test5: PF(host) allmulticast off; VF(guest) allmulticast off; VF trust on"
		rlLog "guest: set allmulticast on capture multicast package"
		ip link set $nic_test allmulticast off
		ip link show $nic_test | grep -e "vf 0" | grep -e "trust on" || { ((result += 1)); rlFail 'VF trust may not be supported!'; }
		ip link show $nic_test

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST allmulticast off}
			{ip link show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{timeout 15s bash -c \"tcpdump -i \${NIC_TEST} -c1 host 225.1.2.3 -p\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		(( $? )) || rlFail "Test5 failed, can capture multicast package from guest"

		##### Test 6
		# set all on, check again
		rlLog "Test6: PF(host) allmulticast on; VF(guest) allmulticast on; VF trust on"
		ip link set $nic_test allmulticast on
		ip link show $nic_test
		ifconfig $nic_test | grep -e "ALLMULTI" || { ((result += 1)); rlFail 'configure allmulticast failed!'; }

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST allmulticast on}
			{ip link show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{timeout 15s bash -c \"tcpdump -i \${NIC_TEST} -c1 host 225.1.2.3 -p \"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		(( $? )) && rlFail "Test6 failed, can't capture multicast package from guest"

		sync_set server $testname_end

		if [[ "$NIC_DRIVER" == "i40e" ]] || [[ "$NIC_DRIVER" == "ice" ]];then
			ethtool --set-priv-flags $nic_test vf-true-promisc-support off
			ethtool --show-priv-flags $nic_test
		fi

		ip link set $nic_test allmulticast off

		sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		sriov_remove_vfs $nic_test 0
	fi

	return $result
}

sriov_test_link_down_on_close()
{
	# bug reproduce for https://bugzilla.redhat.com/show_bug.cgi?id=2024110
	# If reproduce this issue, the test machine needs to be restarted to restore the environment
	ip link set $nic_test up
	ip link show $nic_test
	if i_am_server; then
		sync_set client ${FUNCNAME}_start
		sync_wait client ${FUNCNAME}_end
	else
		if [ ! -f /tmp/sriov_test_link_down_on_close ];then
			sync_wait server ${FUNCNAME}_start
			if [[ "$NIC_DRIVER" == "i40e" ]] || [[ "$NIC_DRIVER" == "ice" ]];then
				rlRun "ethtool --set-priv-flags $nic_test link-down-on-close on"
				local ison=$(ethtool --show-priv-flags ${nic_test} | grep "link-down-on-close" | awk '{ print $3 }')
				if test "$ison" != "on"; then
					rlLogWarning "could not set link down on close"
				fi

				rlRun "ip link set ${nic_test} up"
				local lowerup=$(ip -o link show dev ${nic_test} | grep LOWER_UP)
				if test "x${lowerup}" == "x"; then
					rlFail "lower not up"
				fi

				# set MTU and verify lower up again
				rlRun "ip link set ${nic_test} mtu 9000 up"
				local lowerup=$(ip -o link show dev ${nic_test} | grep LOWER_UP)
				if test -z "${lowerup}"; then
					rlFail "lower not up"
				fi

				rlLog "need to clear the priv flag (turn to off), reset mtu to 1500 and then flap (ip link set down; ip link set up) the link before the NO-CARRIER state will clear."
				rlRun "ip link set ${nic_test} mtu 1500"
				rlRun "ethtool --set-priv-flags $nic_test link-down-on-close off"
				rlRun "ethtool --show-priv-flags ${nic_test}"
				rlRun "ip link set ${nic_test} down"
				rlRun "ip link set ${nic_test} up"
				sleep 30
				rlRun "ip link show ${nic_test}"
				local status=$(ip -o link show dev ${nic_test} | grep LOWER_UP)
				if test -z "${status}"; then
					rlLog "can't reset nic status, need to reboot test server"
					rlRun "touch /tmp/sriov_test_link_down_on_close"
					rhts-reboot
				fi

			fi
			sync_set server ${FUNCNAME}_end
		else
			rlLog "clean test file"
			rlRun "rm -rf /tmp/sriov_test_link_down_on_close"
			sync_set server ${FUNCNAME}_end
		fi
	fi

}

sriov_test_vmvf_vlan_offload_remote()
{
	log_header "VMVF VLAN OFFLOAD<---> REMOTE" $result_file

	local result=0
	local vid=3

	ip link set $nic_test up

	if i_am_server; then
		ip link add link $nic_test name ${nic_test}.${vid} type vlan id $vid
		ip link set ${nic_test}.${vid} up
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr_vlan}.2/24 dev $nic_test.$vid
		ip addr add 2021:db8:${ipaddr_vlan}::2/64 dev $nic_test.$vid

		sync_set client test_vmvf_vlan_offload_remote_start
		sync_wait client test_vmvf_vlan_offload_remote_end

		ip link set ${nic_test}.${vid} down
		ip link del ${nic_test}.${vid}

	else
		sync_wait server test_vmvf_vlan_offload_remote_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_vlan_offload_remote_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
			#   sync_set server test_vmvf_vlan_offload_remote_end
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$vid type vlan id $vid}
				{ip link set \$NIC_TEST.$vid up}
				{ip addr flush \$NIC_TEST.$vid}
				{ip addr add 172.30.${ipaddr_vlan}.11/24 dev \$NIC_TEST.$vid}
				{ip addr add 2021:db8:${ipaddr_vlan}::11/64 dev \$NIC_TEST.$vid}
				{ip link show \$NIC_TEST.$vid}
				{ip addr show \$NIC_TEST.$vid}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST tso off;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set tso off fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST gso off;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set gso off fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST gro off;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set gro off fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST tx off;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set tx off fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST txvlan off;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set txvlan off fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST rxvlan off;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set rxvlan off fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST rx-vlan-filter off;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set rx-vlan-filter off fail"
				result=1
			fi
			if [ $result -eq 0 ];then
				if ! do_vm_netperf $vm1 172.30.${ipaddr_vlan}.2 2021:db8:${ipaddr_vlan}::2 $result_file; then
					result=1
				fi
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST tso on;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set tso on fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST gso on;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set gso on fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST gro on;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set gro on fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST tx on;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set tx on fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST txvlan on;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set txvlan on fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST rxvlan on;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set rxvlan on fail"
				result=1
			fi
			vmsh cmd_set $vm1 "{export NIC_TEST=\`ip link show | grep $mac -B1 | head -n1 | awk -F ':' '{print \$2}'\`;ethtool -K \$NIC_TEST rx-vlan-filter on;ethtool -k \$NIC_TEST}"
			if [ $? -ne 0 ];then
				rlFail "set rx-vlan-filter on fail"
				result=1
			fi
			if [ $result -eq 0 ];then
				if ! do_vm_netperf $vm1 172.30.${ipaddr_vlan}.2 2021:db8:${ipaddr_vlan}::2 $result_file; then
					result=1
				fi
			fi

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_vlan_offload_remote_end

	fi
	return $result
}

sriov_test_trusted_vf_ipv6addr()
{
	log_header "trusted_vf_ipv6addr" $result_file

	local result=0

	ip link set $nic_test up

	local ipaddr_num=32

	local testname=test_trusted_vf_ipv6addr

	if i_am_server;then
		ip -6 addr flush $nic_test
		ip -6 neigh flush dev $nic_test
		for((i=1;i<=$ipaddr_num;i++))
		do
			ip addr add 2021:db8:${ipaddr}:${i}::$((i+1))/64 dev $nic_test
		done
		sleep 5
		sync_set client ${testname}_start
		sync_wait client ${testname}_end
		ip -6 addr flush $nic_test
		ip -6 neigh flush dev $nic_test
	else
		sync_wait server ${testname}_start
		if ! sriov_create_vfs $nic_test 0 2;then
			sync_set server ${testname}_end
			return 1
		else
			local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
				#		sync_set server ${testname}_end
				result=1
			else
				vmsh run_cmd $vm1 "echo \$(ip link | grep $mac -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') > /home/testiface"

				vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface) up"
				sleep 2

				################################################################
				ip link set $nic_test vf 0 trust on
				ip link set $nic_test allmulticast on
				vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface) allmulticast on"

				vmsh run_cmd $vm1 "ip -6 addr flush dev \$(cat /home/testiface)"
				for((i=1;i<=$ipaddr_num;i++))
				do
					#{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					local cmd=(
						{ip addr add 2021:db8:${ipaddr}:${i}::${i}/64 dev \$\(cat /home/testiface\)}
						{ping6 2021:db8:${ipaddr}:${i}::$((i+1)) \&}
						{test \"\$\(tshark -a duration:10 -nVpq -i \$\(cat /home/testiface\) -f \"dst 2021:db8:${ipaddr}:${i}::${i} and src 2021:db8:${ipaddr}:${i}::$((i+1))\" -c1 -T fields -e ipv6.src 2\>/dev/null\)\" = \'2021:db8:${ipaddr}:${i}::$((i+1))\'}
						{pkill ping6}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					if [ $? -ne 0 ];then
						let result+=1
						rlFail "fail: can not config more then 30 ipv6 addr"
						break
					fi

				done

				################################################################
				ip link set $nic_test vf 0 trust off
				ip link set $nic_test allmulticast on
				vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface) allmulticast on"

				vmsh run_cmd $vm1 "ip -6 addr flush dev \$(cat /home/testiface)"
				local ping6_success_count=0
				for((i=1;i<=$ipaddr_num;i++))
				do
					#{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					local cmd=(
						{ip addr add 2021:db8:${ipaddr}:${i}::${i}/64 dev \$\(cat /home/testiface\)}
						{ping6 2021:db8:${ipaddr}:${i}::$((i+1)) \&}
						{test \"\$\(tshark -a duration:10 -nVpq -i \$\(cat /home/testiface\) -f \"dst 2021:db8:${ipaddr}:${i}::${i} and src 2021:db8:${ipaddr}:${i}::$((i+1))\" -c1 -T fields -e ipv6.src 2\>/dev/null\)\" = \'2021:db8:${ipaddr}:${i}::$((i+1))\'}
						{pkill ping6}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					if [ $? -eq 0 ];then
						let ping6_success_count+=1
					fi

				done
				if [ $ping6_success_count -gt 30 ];then
					let result+=1
					rlFail "fail: set vf trust off, but still can config more then 30 ipv6 addr"
				fi

				################################################################
				ip link set $nic_test vf 0 trust on
				ip link set $nic_test allmulticast off
				vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface) allmulticast on"

				vmsh run_cmd $vm1 "ip -6 addr flush dev \$(cat /home/testiface)"
				local ping6_success_count=0
				for((i=1;i<=$ipaddr_num;i++))
				do
					#{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					local cmd=(
						{ip addr add 2021:db8:${ipaddr}:${i}::${i}/64 dev \$\(cat /home/testiface\)}
						{ping6 2021:db8:${ipaddr}:${i}::$((i+1)) \&}
						{test \"\$\(tshark -a duration:10 -nVpq -i \$\(cat /home/testiface\) -f \"dst 2021:db8:${ipaddr}:${i}::${i} and src 2021:db8:${ipaddr}:${i}::$((i+1))\" -c1 -T fields -e ipv6.src 2\>/dev/null\)\" = \'2021:db8:${ipaddr}:${i}::$((i+1))\'}
						{pkill ping6}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					if [ $? -eq 0 ];then
						let ping6_success_count+=1
					fi

				done
				if [ $ping6_success_count -gt 30 ];then
					let result+=1
					rlFail "fail: set pf allmulticast off, but still can config more then 30 ipv6 addr"
				fi

				################################################################
				ip link set $nic_test vf 0 trust on
				ip link set $nic_test allmulticast on
				vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface) allmulticast off"

				vmsh run_cmd $vm1 "ip -6 addr flush dev \$(cat /home/testiface)"
				local ping6_success_count=0
				for((i=1;i<=$ipaddr_num;i++))
				do
					#{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					local cmd=(
						{ip addr add 2021:db8:${ipaddr}:${i}::${i}/64 dev \$\(cat /home/testiface\)}
						{ping6 2021:db8:${ipaddr}:${i}::$((i+1)) \&}
						{test \"\$\(tshark -a duration:10 -nVpq -i \$\(cat /home/testiface\) -f \"dst 2021:db8:${ipaddr}:${i}::${i} and src 2021:db8:${ipaddr}:${i}::$((i+1))\" -c1 -T fields -e ipv6.src 2\>/dev/null\)\" = \'2021:db8:${ipaddr}:${i}::$((i+1))\'}
						{pkill ping6}
					)
					vmsh cmd_set $vm1 "${cmd[*]}"
					if [ $? -eq 0 ];then
						let ping6_success_count+=1
					fi

				done
				if [ $ping6_success_count -gt 30 ];then
					let result+=1
					rlFail "fail: set vf allmulticast off, but still can config more then 30 ipv6 addr"
				fi

				sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			fi
			sriov_remove_vfs $nic_test 0
			sync_set server ${testname}_end
		fi
	fi

	return $result
}


sriov_test_trusted_vf_override_macaddr_via_bonding()
{

	log_header "trusted_vf_override_macaddr_via_bonding" $result_file
	local result=0
	ip link set $nic_test up
	local testname=trusted_vf_override_macaddr_via_bonding

	if i_am_server;then

		ip addr add 172.10.${ipaddr}.2/24 dev $nic_test
		sync_set client ${testname}_start
		sync_wait client ${testname}_end
		ip addr flush dev $nic_test
	fi


	if i_am_client;then
		sync_wait server ${testname}_start
		if ! sriov_create_vfs $nic_test 0 2;then
			sync_set server ${testname}_end
			return 1
		else
			local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
			local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"
			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $nic_test 0 2 $vm1 $mac2;then
					#sync_set server ${testname}_end
				result=1

			else
				vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') > /home/testiface1"
				vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') > /home/testiface2"

				ip link set $nic_test vf 0 trust off
				ip link set $nic_test vf 1 trust off
				ip link set $nic_test vf 0 spoofchk off
				ip link set $nic_test vf 1 spoofchk off

				vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface1) down"
				vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface2) down"

				vmsh run_cmd $vm1 "modprobe -rv bonding"
				vmsh run_cmd $vm1 "modprobe -v bonding max_bonds=1 miimon=100 mode=1 max_bonds=1"
				vmsh run_cmd $vm1 "ip link set bond0 up"
				vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /home/testiface1)"
				if [ $? -ne 0 ];then
					rlFail "fail:can not ifenslave vf 0"
					let result+=1
				else
					vmsh run_cmd $vm1 "ifenslave bond0 \$(cat /home/testiface2)"
					if [ $? -eq 0 ];then
						rlFail "fail:vf 1 trust off, but still can override its mac in vm"
						let result+=1
					else
						ip link set $nic_test vf 1 trust on
						vmsh run_cmd $vm1 "ip link set \$(cat /home/testiface2) up"
						if [ $? -ne 0 ];then
							ehco "fail:vf 1 trust on, but still can not override its mac in vm"
							let result+=1
						else
							vmsh run_cmd $vm1 "ip addr add 172.10.${ipaddr}.3/24 dev bond0"
							vmsh run_cmd $vm1 "ping 172.10.${ipaddr}.2 -c 3"
							if [ $? -ne 0 ];then
									rlFail "fail:ping via bond0 failed"
									let result+=1
							fi
						fi
					fi
				fi

				vmsh run_cmd $vm1 "modprobe -rv bonding"
				sriov_detach_vf_from_vm $nic_test 0 1 $vm1
				sriov_detach_vf_from_vm $nic_test 0 2 $vm1
			fi
		fi
		sriov_remove_vfs $nic_test 0
		sync_set server ${testname}_end
	fi

	return $result
}

sriov_test_bond_failovermac0()
{
local test_name=sriov_test_bond_failovermac0
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}
sriov_test_bond_failovermac0_vlan()
{
	local test_name=sriov_test_bond_failovermac0_vlan
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac1()
{
	local test_name=sriov_test_bond_failovermac1
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac1_pf_down()
{
	local test_name=sriov_test_bond_failovermac1_pf_down
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac1_vlan()
{
	local test_name=sriov_test_bond_failovermac1_vlan
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac2()
{
	local test_name=sriov_test_bond_failovermac2
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac2_swport_down()
{
	$dbg_flag
	local test_name=sriov_test_bond_failovermac2_swport_down
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}

sriov_test_bond_failovermac2_vlan()
{
	local test_name=sriov_test_bond_failovermac2_vlan
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#dont test dualport mlx4 now
				#eval "$test_name"_mlx4en_dualport
				eval "$test_name"_common
				result=$?
			else
				eval "$test_name"_common
				result=$?
			fi
		else
			eval "$test_name"_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		eval "$test_name"_common
		return $?
	fi
}
sriov_test_bond_failovermac0_common() {

	log_header "sriov_test_bond_failovermac0_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		else
			rlFail "lose package more than 200"
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
				! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
				! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		fi
		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase sent interval
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# Increase waiting time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
			if [ $? -ne 0 ]; then
			let result++
				rlFail "failed: failover time is too long"
			fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result
		local cmd=(

			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_failovermac0_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac0_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		if ! sriov_create_vfs $iface1 0 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."

		fi
		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 0 trust on
		ip link set $iface2 vf 0 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
		# reduce sent package interval
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
		# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
			if [ $? -ne 0 ]; then
			let result++
				rlFail "failed: failover time is too long"
			fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result
		local cmd=(

			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0


		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_failovermac0_vlan_common() {

	log_header "sriov_test_bond_failovermac0_vlan_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip addr show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			#increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi

		local cmd=(

			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi


		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}
sriov_test_bond_failovermac0_vlan_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac0_vlan_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac0_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		if ! sriov_create_vfs $iface1 0 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 0 trust on
		ip link set $iface2 vf 0 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=0, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip addr show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi

		local cmd=(

			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$\(cat /tmp/bondmac\) = \$NIC_TEST1_MAC \] \&\& \[ \$NIC_TEST1_MAC = \$NIC_TEST2_MAC \] \&\& \[ \$NIC_TEST2_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi


		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_failovermac1_common() {

	log_header "sriov_test_bond_failovermac1_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test

	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac1_pf_down_common() {

	log_header "sriov_test_bond_failovermac1_pf_down_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1_pf_down

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			rlRun "ip addr add 192.100.1.1/24 dev $nic_test"
		fi
		ip addr show dev $nic_test
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test

	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
				{modprobe -r bonding}
				{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
				{ip link set bond0 up}
				{ifenslave bond0 \$\(cat /tmp/testiface1\)}
				{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = \$ACTIVE_SLAVE_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -eq 0 ];then
			PF_DOWN=$iface1
			PF_UP=$iface2
			echo "PF_DOWN:$PF_DOWN"
		else
			PF_DOWN=$iface2
			PF_UP=$iface1
			echo "PF_DOWN:$PF_DOWN"
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet

		vmsh run_cmd $vm1 "ping $server_ip4 -i 0.01 -c 3000 &"
		#link down the related PF
		ip link set $PF_DOWN down
		ip link show $PF_DOWN

		local cmd=(
			# increase interval time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $PF_UP
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $PF_UP
		sync_set server ${test_name}_end_feedback_result


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
			{ip addr show}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi
	return $result

}

sriov_test_bond_failovermac1_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac1_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64
	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test

	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		if ! sriov_create_vfs $iface1 0 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 0 trust on
		ip link set $iface2 vf 0 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

				if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
						let result++
						rlFail "${test_name} failed: can't attach vf to vm."
				fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
				vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
				{modprobe -r bonding}
				{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
				{ip link set bond0 up}
				{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
				{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_wait server ${test_name}_start_send_packet
			local cmd=(
				# increase interval time
				{ping $server_ip4 -i 0.01 -c 3000 \&}
				{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
				{ip link set \$ACTIVE_SLAVE down}
				# increase wait time
				{sleep 300}
				{pkill ping}
				{modprobe -rv pktgen}
			)
				vmsh cmd_set $vm1 "${cmd[*]}"
				sync_set server ${test_name}_end_send_packet
				sync_wait server ${test_name}_start_feedback_result
				ip addr add 192.100.1.2/24 dev $iface1
				sleep 5
				ping 192.100.1.1 -c 5
				if [ $? -ne 0 ]; then
					let result++
					rlFail "failed: failover time is too long"
				fi
				ip addr del 192.100.1.2/24 dev $iface1
				sync_set server ${test_name}_end_feedback_result


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac1_vlan_common() {

	log_header "sriov_test_bond_failovermac1_vlan_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else

		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}
sriov_test_bond_failovermac1_vlan_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac1_vlan_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac1_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else

		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		if ! sriov_create_vfs $iface1 0 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 0 trust on
		ip link set $iface2 vf 0 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
				vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
			sync_wait server ${test_name}_start_send_packet
			local cmd=(
				# increase interval time
				{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
				{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
				{ip link set \$ACTIVE_SLAVE down}
				# increase wait time
				{sleep 300}
				{pkill ping}
				{modprobe -rv pktgen}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			sync_set server ${test_name}_end_send_packet
			sync_wait server ${test_name}_start_feedback_result
			ip addr add 192.100.1.2/24 dev $iface1
			sleep 5
			ping 192.100.1.1 -c 5
			if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
			fi
			ip addr del 192.100.1.2/24 dev $iface1
			sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}

		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_common() {

	log_header "sriov_test_bond_failovermac2_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
					let result++
					rlFail "${test_name} failed: can't create vfs."
			fi
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			echo "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_swport_down_common() {

	log_header "sriov_test_bond_failovermac2_swport_down_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2_swport_down

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi
		get_iface_sw_port $iface1 sw p1 k || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
		get_iface_sw_port $iface2 sw p2 k || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
# after add port to bond, active slave mac will change to bond mac
#		4: enp6s0: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master bond0 state UP group default qlen 1000
#	link/ether 6e:c3:95:57:2f:7e brd ff:ff:ff:ff:ff:ff permaddr 00:de:ad:23:01:01
#	5: enp11s0: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master bond0 state UP group default qlen 1000
#		link/ether 00:de:ad:23:01:02 brd ff:ff:ff:ff:ff:ff
#	6: bond0: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
#		link/ether 6e:c3:95:57:2f:7e brd ff:ff:ff:ff:ff:ff
#		inet 192.100.35.1/24 scope global bond0
#		   valid_lft forever preferred_lft forever
#		inet6 2021:db02:35::1/64 scope global tentative
#		   valid_lft forever preferred_lft forever
#		inet6 2001::6cc3:95ff:fe57:2f7e/64 scope global dynamic mngtmpaddr
#		   valid_lft 86399sec preferred_lft 14399sec
#		inet6 fe80::6cc3:95ff:fe57:2f7e/64 scope link
#		   valid_lft forever preferred_lft forever

		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST1_MAC=\$\(if ip link show \$\(cat /tmp/testiface1\) \| grep "permaddr" \;then echo \"\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "permaddr" \| awk \'\{print \$2}\'\)\" \;else echo \"\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)\" \;fi\)}
			{export NIC_TEST2_MAC=\$\(if ip link show \$\(cat /tmp/testiface2\) \| grep "permaddr" \;then echo \"\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "permaddr" \| awk \'\{print \$2}\'\)\" \;else echo \"\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)\" \;fi\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BACKUP_SLAVE \| tee /tmp/backupslave}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		#			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{\[ \$ACTIVE_SLAVE_MAC = $mac1 \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -eq 0 ];then
			SW_DOWN=$p1
			PF_DOWN=$iface1
			PF_UP=$iface2
			echo "SW_DOWN:$SW_DOWN"
			echo "PF_DOWN:$PF_DOWN"
		else
			SW_DOWN=$p2
			PF_DOWN=$iface2
			PF_UP=$iface1
			echo "SW_DOWN:$SW_DOWN"
			echo "PF_DOWN:$PF_DOWN"
		fi

		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		vmsh run_cmd $vm1 "ping $server_ip4 -i 0.01 -c 3000 &"
		#link down the related SW port
		swcfg port_down $sw $SW_DOWN
		ip link show $PF_DOWN

		local cmd=(
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $PF_UP
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $PF_UP
		sync_set server ${test_name}_end_feedback_result

		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{\[ \$ACTIVE_SLAVE = \$\(cat /tmp/backupslave\) \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: active backup failed"
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		swcfg port_up $sw $SW_DOWN
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac2_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db02:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db02:${ipaddr}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i $nic_test src ${client_ip4} and dst ${server_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_ip4} > ${server_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		if ! sriov_create_vfs $iface1 0 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 0 trust on
		ip link set $iface2 vf 0 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$NIC_TEST1_MAC = $mac1 \] \&\& \[ \$NIC_TEST2_MAC = $mac2 \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(sed -n 1p /tmp/vfs\) \]\;then sed -n 2p /tmp/vfs\;else sed -n 1p /tmp/vfs\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_bond_failovermac2_vlan_common() {

	log_header "sriov_test_bond_failovermac2_vlan_common" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
			ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		#cxgb4 is different with other NICs when create VFs
		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_create_vfs $iface1 0 1 || \
			! sriov_create_vfs $iface2 1 1;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		else
			if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
			fi
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		else
			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			fi
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
				{modprobe -r bonding}
				{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
				{ip link set bond0 up}
				{ifenslave bond0 \$\(cat /tmp/testiface1\)}
				{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=2, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(cat /tmp/testiface1\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(cat /tmp/testiface2\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"if1: \$\(cat /tmp/testiface1\) if2: \$\(cat /tmp/testiface2\) asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ "\$NIC_TEST1_MAC" = "$mac1" \] \&\& \[ "\$NIC_TEST2_MAC" = "$mac2" \] \&\& \[ "\$ACTIVE_SLAVE_MAC" = "\$BOND_MAC" \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		if [ "$NIC_DRIVER" = "cxgb4" ];then
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 1 1 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 1
		else
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 2 $vm1
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}
sriov_test_bond_failovermac2_vlan_mlx4en_dualport() {

	log_header "sriov_test_bond_failovermac2_vlan_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_failovermac2_vlan

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
			sync_set client ${test_name}_start_send_packet
			sync_wait client ${test_name}_end_send_packet
			pkill tcpdump
			sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
			local packet_lost=$((3000-$packet_received))
			rlLog "packet_lost=$packet_lost"
			if [ $packet_lost -lt 200 ];then
					ip addr add 192.100.1.1/24 dev $nic_test
			fi
			sync_set client ${test_name}_start_feedback_result
			sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		if ! sriov_create_vfs $iface1 0 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."
		fi

		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"


		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=1 miimon=100 fail_over_mac=2 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=2, ifenslave failed";let result++; }
		fi
		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(cat /tmp/testiface1\) \]\;then cat /tmp/testiface2\;else cat /tmp/testiface1\;fi\)}
			{export NIC_TEST1_MAC=\$\(ip link show \$\(sed -n 1p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export NIC_TEST2_MAC=\$\(ip link show \$\(sed -n 2p /tmp/vfs\) \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \$BOND_MAC \| tee /tmp/bondmac}
			{echo \$ACTIVE_SLAVE_MAC \| tee /tmp/activeslavemac}
			{echo \$BACKUP_SLAVE_MAC \| tee /tmp/backupslavemac}
			{echo \"if1: \$\(sed -n 1p /tmp/vfs\) if2: \$\(sed -n 2p /tmp/vfs\) asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ "\$NIC_TEST1_MAC" = "$mac1" \] \&\& \[ "\$NIC_TEST2_MAC" = "$mac2" \] \&\& \[ "\$ACTIVE_SLAVE_MAC" = "\$BOND_MAC" \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			rlFail "${test_name} failed: mac addr check failed"
			let result++
		fi
		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{ip link show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			# increase interval time
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{ip link set \$ACTIVE_SLAVE down}
			# increase wait time
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		sleep 5
		ping 192.100.1.1 -c 5
		if [ $? -ne 0 ]; then
				let result++
				rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after changing active slave"
		fi


		local cmd=(
			{export ACTIVE_SLAVE=\$\(cat /proc/net/bonding/bond0 \| grep \"Currently Active Slave\" \| awk \'\{print \$NF\}\' \| sed \'s/\*\. //g\'\)}
			{export BACKUP_SLAVE=\$\(if \[ \$ACTIVE_SLAVE = \$\(sed -n 1p /tmp/vfs\) \]\;then sed -n 2p /tmp/vfs\;else sed -n 1p /tmp/vfs\;fi\)}
			{export ACTIVE_SLAVE_MAC=\$\(ip link show \$ACTIVE_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BACKUP_SLAVE_MAC=\$\(ip link show \$BACKUP_SLAVE \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{export BOND_MAC=\$\(ip link show bond0 \| grep "link/ether" \| awk \'\{print \$2\}\'\)}
			{echo \"asl: \$ACTIVE_SLAVE bsl: \$BACKUP_SLAVE activemac: \$ACTIVE_SLAVE_MAC backmac: \$BACKUP_SLAVE_MAC bondmac: \$BOND_MAC tmpbondmac: \$\(cat /tmp/bondmac\) tmpactivemac: \$\(cat /tmp/activeslavemac\) tmpbackmac: \$\(cat /tmp/backupslavemac\)\"}
			{\[ \$BOND_MAC = \$\(cat /tmp/bondmac\) \] \&\& \[ \$BACKUP_SLAVE_MAC = \$\(cat /tmp/backupslavemac\) \] \&\& \[ \$ACTIVE_SLAVE_MAC = \$BOND_MAC \]}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: check mac failed after changing active slave"
		fi
		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0
		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_vmvf_different_vlan()
{
	log_header "VMVF DIFFERENT VLAN <---> REMOTE" $result_file

	local result=0
	local vid1=2
	local vid2=3

		ip link set $nic_test up

		if i_am_server; then
			ip link add link $nic_test name ${nic_test}.${vid1} type vlan id $vid1
			ip link set ${nic_test}.${vid1} up
			ip addr flush $nic_test
			ip addr add 172.30.${ipaddr_vlan}.2/24 dev $nic_test.$vid1
			ip addr add 2021:db8:${ipaddr_vlan}::2/64 dev $nic_test.$vid1

			sync_set client test_vmvf_different_vlan_start
			sync_wait client test_vmvf_different_vlan_end

			ip link set ${nic_test}.${vid1} down
			ip link del ${nic_test}.${vid1}
		else
			sync_wait server test_vmvf_different_vlan_start

			local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
			local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

			if ! sriov_create_vfs $nic_test 0 2; then
				sync_set server test_vmvf_different_vlan_end
				return 1
			fi

			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac1; then
					result=1
			else
				local cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST up}
					{ip addr flush \$NIC_TEST}
					{ip link add link \$NIC_TEST name \$NIC_TEST.$vid2 type vlan id $vid2}
					{ip link set \$NIC_TEST.$vid2 up}
					{ip addr flush \$NIC_TEST.$vid2}
					{ip addr add 172.30.${ipaddr_vlan}.11/24 dev \$NIC_TEST.$vid2}
					{ip addr add 2021:db8:${ipaddr_vlan}::11/64 dev \$NIC_TEST.$vid2}
					{ip link show \$NIC_TEST.$vid2}
					{ip addr show \$NIC_TEST.$vid2}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				sleep 5
				vmsh run_cmd $vm1 "ping -c10 172.30.${ipaddr_vlan}.2"
				(( $? )) || { (( result += 1 ));rlFail "fail:ping remote success between different vlan"; }
							vmsh run_cmd $vm1 "ping6 -c10 2021:db8:${ipaddr_vlan}::2"
				(( $? )) || { (( result += 1 ));rlFail "fail:ping6 remote success between different vlan"; }

				if ! sriov_attach_vf_to_vm $nic_test 0 2 $vm2 $mac2; then
							result=1
				else
					local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip link set \$NIC_TEST up}
						{ip addr flush \$NIC_TEST}
						{ip link add link \$NIC_TEST name \$NIC_TEST.$vid1 type vlan id $vid1}
						{ip link set \$NIC_TEST.$vid1 up}
						{ip addr flush \$NIC_TEST.$vid1}
						{ip addr add 172.30.${ipaddr_vlan}.12/24 dev \$NIC_TEST.$vid1}
						{ip addr add 2021:db8:${ipaddr_vlan}::12/64 dev \$NIC_TEST.$vid1}
						{ip link show \$NIC_TEST.$vid1}
						{ip addr show \$NIC_TEST.$vid1}
					)
					vmsh cmd_set $vm2 "${cmd[*]}"
					sleep 5
					vmsh run_cmd $vm2 "ping -c10 172.30.${ipaddr_vlan}.11"
					(( $? )) || { (( result += 1 ));rlFail "fail:ping vm1 success between different vlan"; }
					vmsh run_cmd $vm2 "ping6 -c10 2021:db8:${ipaddr_vlan}::11"
					(( $? )) || { (( result += 1 ));rlFail "fail:ping6 vm1 success between different vlan"; }
					sriov_detach_vf_from_vm $nic_test 0 2 $vm2
				fi
				sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_different_vlan_end
	fi

	return $result
}

#
#  ioctl(FIONREAD) returns zero length on ixgbevf and IPv6 SCTP raw socket
#
sriov_test_bz1441909()
{
	log_header "sriov_test_bz1441909" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.10/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::10/64 dev $nic_test
		gcc ./bz1441909/v6send.c -o v6send
		sync_set client test_bz1441909_start
		sync_wait client test_bz1441909_ready_receive
		./v6send 2021:db8:${ipaddr}::10 2021:db8:${ipaddr}::11 ./bz1441909/data 1
		sync_set client test_bz1441909_sent
		sync_wait client test_bz1441909_end
		ip addr flush $nic_test
	else
		sync_wait server test_bz1441909_start
		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			result=1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		fi
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip addr flush \$NIC_TEST}
			{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
			{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
			{ip link show \$NIC_TEST}
			{ip addr show \$NIC_TEST}
			{cp -u ${CASE_PATH}/bz1441909/v6recv.c ./}
			{gcc v6recv.c -o v6recv}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		vmsh run_cmd $vm1 "timeout 120s bash -c \"until ping6 -c3 2021:db8:${ipaddr}::10; do sleep 5; done\""
		vmsh run_cmd $vm1 "./v6recv 2021:db8:${ipaddr}::11 > /home/bz1441909.log 2>&1 &"
		sync_set server test_bz1441909_ready_receive
		sync_wait server test_bz1441909_sent
		sleep 3
		local cmd=(
			{pkill v6recv}
			{sleep 2}
			{grep -c \'ioctl\(\) FIONREAD read 0 bytes ready\' /home/bz1441909.log}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		(( $? )) || { result=1;rlFail "fail:FIONREAD read 0 bytes"; }
		sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		sriov_remove_vfs $nic_test 0
		sync_set server test_bz1441909_end
	fi

	return $result
}

sriov_test_bond_lacp()
{
	$dbg_flag
	if i_am_client;then
		local result=0
		OLD_NIC_NUM=$NIC_NUM
		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test ifs: $iface1 $iface2"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "two ifs belong to a dual port NIC"
			if [ "$NIC_DRIVER" = "mlx4_en" ];then
				#don't test dualport mlx4 now
				#sriov_test_bond_lacp_mlx4en_dualport
				sriov_test_bond_lacp_common
				result=$?
			elif [ "$NIC_DRIVER" = "cxgb4" ];then
				sriov_test_bond_lacp_cxgb4
				result=$?
			else
				sriov_test_bond_lacp_common
				result=$?
			fi
		else
			sriov_test_bond_lacp_common
			result=$?
		fi
		NIC_NUM=$OLD_NIC_NUM
		return $result
	else
		sriov_test_bond_lacp_common
		return $?
	fi
}

sriov_test_bond_lacp_common() {

	log_header "sriov_test_bond_lacp_common" $result_file

	local result=0
	local test_name=sriov_test_bond_lacp

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local pf_ip4="192.100.${ipaddr}.3"

	local vlan_id=3

	local server_vlanif_mac="22:22:11:11:11:10"

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		ip link set ${nic_test}.${vlan_id} address $server_vlanif_mac
		ip addr show $nic_test
		ip addr show ${nic_test}.${vlan_id}
		nic_mac=$(get_iface_mac $nic_test)
		local S_beaker_if=$(get_default_iface)
		local S_beaker_ip4=$(get_iface_ip4 $S_beaker_if)
		rlLog "nic_mac: $nic_mac"
		rlLog "Server_beaker_ip4: $S_beaker_ip4"
		sync_wait client ${test_name}_ready_to_receive_mac
		timeout 60s bash -c "until ping  ${pf_ip4} -c 5; do sleep 5; done"
		echo $nic_mac|nc ${pf_ip4} 1234
		echo $S_beaker_ip4|nc ${pf_ip4} 1235
		sync_set client ${test_name}_finish_to_receive_beaker_mac
		sync_wait client ${test_name}_done_to_receive_beaker_mac

		nc -l 1236 > /tmp/client_beaker_ip &
		sync_set client ${test_name}_ready_to_receive_beaker_ip
		sync_wait client ${test_name}_finish_to_receive_beaker_ip
		local remote_beaker_ip=$(cat /tmp/client_beaker_ip)
		echo "remote_beaker_ip: $remote_beaker_ip"
		sync_set client ${test_name}_start

		sync_wait client ${test_name}_ready_send_packet
		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result
		ping $remote_beaker_ip -c 5
		echo $packet_received|nc ${remote_beaker_ip} 12345
		echo "packet_received=$packet_received"
		sync_set client ${test_name}_nc12345

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local beaker_if=$(get_default_iface)
		local beaker_ip4=$(get_iface_ip4 $beaker_if)
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		ip link set $iface1 up
		ip addr add ${pf_ip4}/${ip4_mask_len} dev ${iface1}
		nc -l 1234 > /tmp/remote_mac &
		nc -l 1235 > /tmp/remote_beaker_ip &
		ip addr show $iface1
		rlLog "beaker_ip: $beaker_ip4"
		sync_set server ${test_name}_ready_to_receive_mac
		sync_wait server ${test_name}_finish_to_receive_beaker_mac
		sync_set server ${test_name}_done_to_receive_beaker_mac

		local remote_ip=$(cat /tmp/remote_beaker_ip)
		rlLog "remote_ip: $remote_ip"
		sync_wait server ${test_name}_ready_to_receive_beaker_ip
		echo $beaker_ip4|nc ${remote_ip} 1236
		sync_set server ${test_name}_finish_to_receive_beaker_ip
		sync_wait server ${test_name}_start
		remote_mac=$(cat /tmp/remote_mac)
		echo "remote_mac: $remote_mac"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if [ "$if1_bus" = "$if2_bus" ];then
			rlLog "warning: two ifs belong to a dual port NIC"
		fi
		if ! sriov_create_vfs $iface1 0 2 || \
				! sriov_create_vfs $iface2 0 2;then
			let result++
			rlFail "${test_name} failed: can't create vfs."

		fi
		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"
		local mac3="00:de:ad:$(printf %02x $ipaddr):01:03"
		local mac4="00:de:ad:$(printf %02x $ipaddr):01:04"
		local mac5="00:de:ad:$(printf %02x $ipaddr):01:05"
		local mac6="00:de:ad:$(printf %02x $ipaddr):01:06"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 0 2 $vm1 $mac2;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi
		get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
		swcfg_port_channel $switch_name "$port_list" "active" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
		if [ -n "$kick_list" ];then
			rlLog "$kick_list are not on the same switch, kicked."
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}' | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=802.3ad miimon=100 max_bonds=1}
			{ip link set bond0 up}
			{ls -l}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
			{sleep 2}
			{cat \/proc\/net\/bonding\/bond0}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlLog "${test_name} failed:ifenslave failed";let result++; }
		fi
#	src_mac_num=$(echo $mac1 | cut -f6 -d ':')
#	dst_mac_num=$(echo $remote_mac | cut -f6 -d ':')
#	out_if_idx=$(((16#${src_mac_num} ^ 16#${dst_mac_num} ^ 16#0800) % 2))
#
#	vlan_src_mac_num=$(echo $mac1 | cut -f6 -d ':')
#	vlan_dst_mac_num=$(echo $server_vlanif_mac | cut -f6 -d ':')
#	vlan_out_if_idx=$(((16#${vlan_src_mac_num} ^ 16#${vlan_dst_mac_num} ^ 16#0800) % 2))

		local cmd=(
			{ip link set bond0 down}
			{echo layer2 \> \/sys\/class\/net\/bond0\/bonding\/xmit_hash_policy}
			{ip link set bond0 up}
			{ip link set bond0 address $mac3 }
			{cat \/proc\/net\/bonding\/bond0}
			{sleep 3}
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{timeout 120s bash -c \"until ping -c 10 $server_ip4\; do sleep 5\; done\"}
			{timeout 120s bash -c \"until ping -c 10 $server_ip6\; do sleep 5\; done\"}
			{sleep 3}
			{ip addr show}
			{ls -l}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping -c20 $server_ip4}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n | grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream1_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream1_outif=if0
			else
				let result++
				rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi

		local cmd=(
			{ip link set bond0 address $mac4}
			{cat \/proc\/net\/bonding\/bond0}
			{sleep 3}
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping $server_ip4 -c20}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n |grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream2_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream2_outif=if0
			else
				let result++
			rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi
		if [ x"${stream1_outif}" == x"${stream2_outif}" ]; then
			let result++
			rlFail "${test_name} failed: two streams dispatched to a same interface. ${stream1_outif} vs ${stream2_outif}"
		else
			rlLog "${test_name} success: two streams dispatched to different interface. ${stream1_outif} vs ${stream2_outif}"
		fi


		local cmd=(
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id address $mac5}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{cat \/proc\/net\/bonding\/bond0}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip4\; do sleep 5\; done\"}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip6\; do sleep 5\; done\"}
			{sleep 3}
			{ip addr show}
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			#{tcpdump -i \$\(cat /tmp/testiface1\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if0.cap \&}
			#{tcpdump -i \$\(cat /tmp/testiface2\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if1.cap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_vlanif_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_vlanif_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping $server_vlanif_ip4 -c20}
			{ pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n | grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream3_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream3_outif=if0
			else
				let result++
				rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi
		local cmd=(
			{ip link set bond0\.$vlan_id address $mac6}
			{cat \/proc\/net\/bonding\/bond0}
			{sleep 3}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip4\; do sleep 5\; done\"}
			{timeout 120s bash -c \"until ping -c 10 $server_vlanif_ip6\; do sleep 5\; done\"}
			{sleep 3}
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			{tcpdump -p -i \$\(cat /tmp/testiface1\) \"icmp and dst $server_vlanif_ip4 \" -w if0.pcap \&}
			{tcpdump -p -i \$\(cat /tmp/testiface2\) \"icmp and dst $server_vlanif_ip4 \" -w if1.pcap \&}
			{sleep 3}
			{ping $server_vlanif_ip4 -c20}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if0.pcap -n | grep -i 'echo request'}"
		if [ $? -ne 0 ];then # can't capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				let result++
				rlFail "${test_name} failed: can't capture packages from all of slave port"
			else
				rlLog "capture packages from if1"
				local stream4_outif=if1
			fi
		else # can capture packages from if0
			vmsh cmd_set $vm1 "{tcpdump -r if1.pcap -n | grep -i 'echo request'}"
			if [ $? -ne 0 ]; then # can't capture packages from if1
				rlLog "capture packages from if0"
				local stream4_outif=if0
			else
				let result++
				rlFail "${test_name} failed: can capture packages from all of slave port"
			fi
		fi
		if [ x"${stream3_outif}" == x"${stream4_outif}" ]; then
			let result++
			rlFail "${test_name} failed: two streams dispatched to a same interface. ${stream3_outif} vs ${stream4_outif}"
		else
			rlLog "two streams dispatched to different interface. ${stream3_outif} vs ${stream4_outif}"
		fi

#		local cmd=(
#			{tcpdump -i \$\(cat /tmp/testiface1\) -w if0.cap \&}
#			{tcpdump -i \$\(cat /tmp/testiface2\) -w if1.cap \&}
#			{sleep 2}
#			{ping ${server_ip4} -c3}
#			{pkill tcpdump}
#			{sleep 2}
#			{ls -l \| grep if}
#		)
#		vmsh cmd_set $vm1 "${cmd[*]}"
#		if [ $? -ne 0 ];then
#			let result++
#			echo "${test_name} failed: ping failed via bond0"
#		fi
#		vmsh cmd_set $vm1 "{tcpdump -r if${out_if_idx}.cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
#		if [ $? -ne 0 ];then
#			let result++
#			echo "${test_name} failed: packet was not sent from if ${out_if_idx}"
#		fi
#		vmsh cmd_set $vm1 "{tcpdump -r if$(((${out_if_idx}+1)%2)).cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
#		if [ $? -eq 0 ];then
#			let result++
#			echo "${test_name} failed: packet was sent from wrong if"
#		fi
		sync_set server ${test_name}_ready_send_packet
		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			#increase interval time
			{rm -rf \/root\/if0.pcap}
			{rm -rf \/root\/if1.pcap}
			{ls -l}
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		rlRun "ip link set $iface1 down"
		local cmd=(
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		rlLog "start nc on 12345"
		nc -l 12345 > /tmp/remote_received_packets &
		sync_set server ${test_name}_end_feedback_result
		sync_wait server ${test_name}_nc12345
		local packets_num=$(cat /tmp/remote_received_packets)
		if [ ! -n "$packets_num" ] ; then
			let result++
			rlFail "failed: no packets, or failover time is too long"
		elif [ $packets_num -lt 2800 ];then
			let result++
			rlFail "failed: failover time is too long"
		fi
		rlLog "remote_receive_packets_num $packets_num"
		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after link down slave"
		fi

		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		cleanup_swcfg

		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_detach_vf_from_vm $iface2 0 2 $vm1
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0

		ip addr flush $iface1
		ip addr flush $iface2
		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_bond_lacp_cxgb4() {

	log_header "sriov_test_bond_lacp_cxgb4" $result_file

	local result=0
	local test_name=sriov_test_bond_lacp

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local pf_ip4="192.100.${ipaddr}.3"

	local vlan_id=3

	local server_vlanif_mac="22:22:11:11:11:10"

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		ip link set ${nic_test}.${vlan_id} address $server_vlanif_mac
		ip addr show $nic_test
		ip addr show ${nic_test}.${vlan_id}
		nic_mac=$(get_iface_mac $nic_test)
		rlLog "nic_mac: $nic_mac"
		sync_wait client ${test_name}_ready_to_receive_mac
		timeout 60s bash -c "until ping  ${pf_ip4} -c 5; do sleep 5; done"
		echo $nic_mac|nc ${pf_ip4} 1234
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		ip link set $iface1 up
		ip addr add ${pf_ip4}/${ip4_mask_len} dev ${iface1}
		nc -l 1234 > /tmp/remote_mac &
		ip addr show $iface1
		sync_set server ${test_name}_ready_to_receive_mac
		sync_wait server ${test_name}_start
		remote_mac=$(cat /tmp/remote_mac)
		rlLog "remote_mac: $remote_mac"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		if ! sriov_create_vfs $iface1 0 1 || \
				! sriov_create_vfs $iface2 1 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."

		fi
		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 1 1 $vm1 $mac2;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi
		get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
		swcfg_port_channel $switch_name "$port_list" "active" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
		if [ -n "$kick_list" ];then
			rlFail "$kick_list are not on the same switch, kicked."
		fi

		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"
		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=802.3ad miimon=100 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(cat /tmp/testiface1\)}
			{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed:ifenslave failed";let result++; }
		fi
		src_mac="0x${mac1//:/}"
		dst_mac="0x${remote_mac//:/}"
		out_if_idx=$(((${src_mac}^${dst_mac}^0x0800)%2))

		vlan_src_mac="0x${mac1//:/}"
		vlan_dst_mac="0x${server_vlanif_mac//:/}"
		vlan_out_if_idx=$(((${vlan_src_mac}^${vlan_dst_mac}^0x0800)%2))

		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{sleep 50}
			{ip addr show}
			#{tcpdump -i \$\(cat /tmp/testiface1\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if0.cap \&}
			#{tcpdump -i \$\(cat /tmp/testiface2\) icmp and src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} -w if1.cap \&}
			{tcpdump -i \$\(cat /tmp/testiface1\) -w if0.cap \&}
			{tcpdump -i \$\(cat /tmp/testiface2\) -w if1.cap \&}
			{sleep 2}
			{ping ${server_vlanif_ip4} -c3}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if${vlan_out_if_idx}.cap -n|grep \"${client_vlanif_ip4} > ${server_vlanif_ip4}\"}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: packet was not sent from vlan if ${vlan_out_if_idx}"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if$(((${vlan_out_if_idx}+1)%2)).cap -n|grep \"${client_vlanif_ip4} > ${server_vlanif_ip4}\"}"
		if [ $? -eq 0 ];then
			let result++
			rlFail "${test_name} failed: packet was sent from wrong vlan if"
		fi
		local cmd=(
			{tcpdump -i \$\(cat /tmp/testiface1\) -w if0.cap \&}
			{tcpdump -i \$\(cat /tmp/testiface2\) -w if1.cap \&}
			{sleep 2}
			{ping ${server_ip4} -c3}
			{pkill tcpdump}
			{sleep 2}
			{ls -l \| grep if}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if${out_if_idx}.cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: packet was not sent from if ${out_if_idx}"
		fi
		vmsh cmd_set $vm1 "{tcpdump -r if$(((${out_if_idx}+1)%2)).cap -n|grep \"${client_ip4} > ${server_ip4}\"}"
		if [ $? -eq 0 ];then
			let result++
			rlFail "${test_name} failed: packet was sent from wrong if"
		fi


		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		rlRun "ip link set $iface1 down"
		local cmd=(
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface2
		timeout 60s bash -c "until ping 192.100.1.1 -c 5; do sleep 5; done"
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface2
		sync_set server ${test_name}_end_feedback_result

		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after link down slave"
		fi

		#if ! do_vm_netperf $vm1 ${server_ip4} ${server_ip6} $result_file;then
		#	let result++
		#fi
		#if ! do_vm_netperf $vm1 ${server_vlanif_ip4} ${server_vlanif_ip6} $result_file;then
		#	let result++
		#fi
		cleanup_swcfg

		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_detach_vf_from_vm $iface2 1 1 $vm1
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 1

		ip addr flush $iface1
		ip addr flush $iface2

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}
sriov_test_bond_lacp_mlx4en_dualport() {

	log_header "sriov_test_bond_lacp_mlx4en_dualport" $result_file

	local result=0
	local test_name=sriov_test_bond_lacp

	local server_ip4="192.100.${ipaddr}.2"
	local server_ip6="2021:db01:${ipaddr}::2"
	local client_ip4="192.100.${ipaddr}.1"
	local client_ip6="2021:db01:${ipaddr}::1"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local client_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local pf_ip4="192.100.${ipaddr}.3"

	local vlan_id=3

	local server_vlanif_mac="22:22:11:11:11:10"

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		ip link set ${nic_test}.${vlan_id} address $server_vlanif_mac
		ip addr show $nic_test
		ip addr show ${nic_test}.${vlan_id}
		nic_mac=$(get_iface_mac $nic_test)
		rlLog "nic_mac: $nic_mac"
		sync_wait client ${test_name}_ready_to_receive_mac
		timeout 60s bash -c "until ping  ${pf_ip4} -c 5; do sleep 5; done"
		echo $nic_mac|nc ${pf_ip4} 1234
		sync_set client ${test_name}_start

		rm -f failover.cap
		tcpdump -i ${nic_test}.${vlan_id} src ${client_vlanif_ip4} and dst ${server_vlanif_ip4} and icmp -w failover.cap &
		sync_set client ${test_name}_start_send_packet
		sync_wait client ${test_name}_end_send_packet
		pkill tcpdump
		sleep 1
		local packet_received=`tcpdump -r failover.cap -nn | grep "${client_vlanif_ip4} > ${server_vlanif_ip4}" | wc -l`
		local packet_lost=$((3000-$packet_received))
		rlLog "packet_lost=$packet_lost"
		if [ $packet_lost -lt 200 ];then
				ip addr add 192.100.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_start_feedback_result
		sync_wait client ${test_name}_end_feedback_result

		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		local iface1=$(echo $test_iface | awk '{print $1}')
		local iface2=$(echo $test_iface | awk '{print $2}')
		ip link set $iface1 up
		ip addr add ${pf_ip4}/${ip4_mask_len} dev ${iface1}
		nc -l 1234 > /tmp/remote_mac &
		ip addr show $iface1
		sync_set server ${test_name}_ready_to_receive_mac
		sync_wait server ${test_name}_start
		remote_mac=$(cat /tmp/remote_mac)
		rlLog "remote_mac: $remote_mac"
		local if1_bus=$(sriov_get_pf_bus_info $iface1 0)
		local if2_bus=$(sriov_get_pf_bus_info $iface2 0)
		#vf will be created paired on dual port mlx NIC
		if ! sriov_create_vfs $iface1 0 1;then
			let result++
			rlFail "${test_name} failed: can't create vfs."

		fi
		ip link set $iface1 up
		ip link set $iface2 up
		sleep 10

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 0 trust on
		ip link set $iface2 vf 0 spoofchk off

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_vf; done"

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_vf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_vf; done"
		vmsh run_cmd $vm1 "diff /tmp/nic_list_without_vf /tmp/nic_list_with_vf|grep \">\"|awk '{print \$2}' | tee /tmp/vfs"

		get_iface_sw_port "$iface1 $iface2" switch_name port_list kick_list || { rlFail "failed:get_iface_sw_port failed";let exitcode++; }
		swcfg_port_channel $switch_name "$port_list" "active" || { rlFail "failed:swcfg_port_channel failed";let exitcode++; }
		if [ -n "$kick_list" ];then
			rlLog "$kick_list are not on the same switch, kicked."
		fi

		vmsh run_cmd $vm1 "ip link set \$(sed -n 1p /tmp/vfs) down"
		vmsh run_cmd $vm1 "ip link set \$(sed -n 2p /tmp/vfs) down"

		local cmd=(
			{modprobe -r bonding}
			{modprobe -v bonding mode=802.3ad miimon=100 max_bonds=1}
			{ip link set bond0 up}
			{ifenslave bond0 \$\(sed -n 1p /tmp/vfs\)}
			{ifenslave bond0 \$\(sed -n 2p /tmp/vfs\)}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed:ifenslave failed";let result++; }
		fi

		local cmd=(
			{ip addr add ${client_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client_ip6}/${ip6_mask_len} dev bond0}
			{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
			{ip link set bond0\.$vlan_id up}
			{ip addr add ${client_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
			{ip addr add ${client_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
			{sleep 50}
			{ip addr show}
			{ping ${server_vlanif_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0.${vlan_id} "
		fi
		local cmd=(
			{ping ${server_ip4} -c3}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0"
		fi

		sync_wait server ${test_name}_start_send_packet
		local cmd=(
			{ping $server_vlanif_ip4 -i 0.01 -c 3000 \&}
			{ip link set \$\(sed -n 1p /tmp/vfs\) down}
			{sleep 300}
			{pkill ping}
			{modprobe -rv pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server ${test_name}_end_send_packet
		sync_wait server ${test_name}_start_feedback_result
		ip addr add 192.100.1.2/24 dev $iface1
		timeout 60s bash -c "until ping 192.100.1.1 -c 5; do sleep 5; done"
		if [ $? -ne 0 ]; then
			let result++
			rlFail "failed: failover time is too long"
		fi
		ip addr del 192.100.1.2/24 dev $iface1
		sync_set server ${test_name}_end_feedback_result


		vmsh run_cmd $vm1 "ping ${server_ip4} -c3"
		if [ $? -ne 0 ];then
			let result++
			rlFail "${test_name} failed: ping failed via bond0 after link down slave"
		fi

		cleanup_swcfg

		local cmd=(
			{ip link del bond0\.${vlan_id}}
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sriov_detach_vf_from_vm $iface1 0 1 $vm1
		sriov_remove_vfs $iface1 0

		ip addr flush $iface1
		ip addr flush $iface2
		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

# if nic is in promiscuous mode, it can receives all packets no matter if the packet's dst_mac equal nic's mac
# if the vf is trust on, user can set vf to promiscuous mode on VM, otherwise can't.
sriov_test_trusted_vf_promisc()
{
		log_header "trusted_vf_promisc" $result_file

		local result=0

		ip link set $nic_test up
		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
		local pktgen_dst_mac="00:de:ad:$(printf %02x $ipaddr):01:02"

		if i_am_server; then
				ip addr flush $nic_test
				ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
				ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

				sync_wait client test_trusted_vf_promisc_start

				rlRun "modprobe pktgen"
				sleep 5
				rlRun "echo rem_device_all > /proc/net/pktgen/kpktgend_0"
				rlRun "echo add_device $nic_test > /proc/net/pktgen/kpktgend_0"
				rlRun "test -f /proc/net/pktgen/$nic_test"
				rlRun "echo dst_mac $pktgen_dst_mac > /proc/net/pktgen/$nic_test"
				rlRun "echo count 360 > /proc/net/pktgen/$nic_test"
				rlRun "echo delay 1000000000 > /proc/net/pktgen/$nic_test"
				rlRun "echo pkt_size 1500 > /proc/net/pktgen/$nic_test"
				rlRun "echo dst 1.1.1.1 > /proc/net/pktgen/$nic_test"
				sync_set client PROMISC_TEST_SEND 360
				rlRun "echo start > /proc/net/pktgen/pgctrl"
				sync_wait client PROMISC_TEST_DONE 360
				rlRun "echo rem_device_all > /proc/net/pktgen/kpktgend_0"
				rlRun "modprobe -r pktgen"

				sync_wait client test_trusted_vf_promisc_end

				ip addr flush $nic_test
		else
				sync_set server test_trusted_vf_promisc_start
				ip link set $nic_test promisc off
				local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

				sriov_create_vfs $nic_test 0 1

				ip link show $nic_test | grep "trust on" && { result=1;rlFail "failed: vf default trust on"; }

				if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
						result=1
				fi

				# trust vf is off by default, promisc should be disabled by default
				rlLog "Test1: trust vf is off by default, the promisc of vf should be disabled by default on the guest"
				local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip link set \$NIC_TEST up}
						{sleep 1}
						{ip addr flush \$NIC_TEST}
						{sleep 1}
						{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
						{sleep 1}
						{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
						{sleep 1}
						{ip link show \$NIC_TEST}
						{sleep 1}
						{ip addr show \$NIC_TEST}
						{sleep 1}
						{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				sync_wait server PROMISC_TEST_SEND
				local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{test \"\$\(tshark -a duration:10 -nVq -i \$NIC_TEST -f \"ether dst $pktgen_dst_mac\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'1.1.1.1\'}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -eq 0 ];then
						result=1
						rlFail "failed: promisc default is off, but still received pktgen_dst_mac"
				fi

				# trust vf is on, enable vf promisc
				rlLog "Test2: set trust vf is on, set promisc is on in the guest"
				rlRun "ip link set $nic_test vf 0 trust on"
				local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{ip addr show \$NIC_TEST}
						{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
						{ip link set \$NIC_TEST promisc on}
						{sleep 1\;ip link show \$NIC_TEST\;ip -d link show \$NIC_TEST \| grep \"promiscuity 1\"}
						{sleep 2}
						{test \"\$\(tshark -a duration:10 -nVq -i \$NIC_TEST -f \"ether dst $pktgen_dst_mac\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'1.1.1.1\'}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -ne 0 ];then
						result=1
						rlFail "failed: promisc on, but can't receive pktgen_dst_mac"
				fi
				# trust vf is on, disable vf promisc
				rlLog "Test3: set trust is on, disable vf promisc in the guest"
				local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
						{ip link set \$NIC_TEST promisc off}
						{sleep 1\;ip -d link show \$NIC_TEST \| grep \"promiscuity 0\"}
						{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -ne 0 ];then
						result=1
						rlFail "failed: error when trust vf is on, disable vf promisc"
				fi
				local cmd=(
						{test \"\$\(tshark -a duration:10 -nVpq -i \$NIC_TEST -f \"ether dst $pktgen_dst_mac\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'1.1.1.1\'}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -eq 0 ];then
						result=1
						rlFail "failed: promisc off, but still received pktgen_dst_mac"
				fi

				# disable trust vf
				rlLog "Test4: disable trust vf, set promisc on in the guest"
				ip link set $nic_test vf 0 trust off
				local cmd=(
						{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
						{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
						{ip link set \$NIC_TEST promisc on}
						{sleep 2}
						{test \"\$\(tshark -a duration:10 -nVq -i \$NIC_TEST -f \"ether dst $pktgen_dst_mac\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'1.1.1.1\'}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -eq 0 ];then
						result=1
						rlFail "failed: trust vf off, but can set vf promisc on in vm"
				fi
				sync_set server PROMISC_TEST_DONE

				sriov_detach_vf_from_vm $nic_test 0 1 $vm1

				sriov_remove_vfs $nic_test 0

				sync_set server test_trusted_vf_promisc_end
		fi

		return $result
}

sriov_test_trusted_vf_promisc_vlan()
{
	log_header "test_trusted_vf_promisc_vlan" $result_file
	local result=0
	ip link set ${nic_test} up
	local vf_0_mac="00:de:ad:$(printf %02x $ipaddr):01:01"
	local vf_1_mac="00:de:ad:$(printf %02x $ipaddr):01:02"
	local server_mac="00:de:ad:$(printf %02x $ipaddr):01:21"

	if  i_am_server; then
		ip addr flush ${nic_test}
		ip link set ${nic_test} down
		sleep 1
		ip link set ${nic_test} address ${server_mac}
		ip link set ${nic_test} up
		ip link set ${nic_test} promisc on
		ip link show ${nic_test}
		ip addr add 172.30.${ipaddr}.2/24 dev ${nic_test}
		sync_set client configure_finished
		for trust_conf in {on,off}
		do
			rlLog "=====Check trust ${trust_conf}====="
			rlLog "Start unicast packets test"
			#unicast
			sync_wait client trust_${trust_conf}_send_unicast_packets_start
			unicast_pkt="Ether(src='${server_mac}', dst='${vf_0_mac}')/Dot1Q(vlan=100)/IP(src='172.30.${ipaddr}.2', dst='172.30.${ipaddr}.3')"
			if [ $(GetDistroRelease) = 8 ];then
				/usr/libexec/platform-python -c  "from scapy.all import *; sendp($unicast_pkt, iface='$nic_test', count=10 )"
			else
				python -c  "from scapy.all import *; sendp($unicast_pkt, iface='$nic_test', count=10)"
			fi
			sleep 60
			sync_set client trust_${trust_conf}_send_unicast_packets_finished
			#multicast
			rlLog "Start multicast packets test"
			sync_wait  client trust_${trust_conf}_send_multicast_packets_start
			multicast_pkt="Ether(src='${server_mac}', dst='01:00:5e:00:00:01')/Dot1Q(vlan=100)/IP(src='172.30.${ipaddr}.2', dst='224.1.2.3')"
			if [ $(GetDistroRelease) = 8 ];then
				/usr/libexec/platform-python -c  "from scapy.all import *; sendp($multicast_pkt, iface='$nic_test', count=10 )"
			else
				python -c  "from scapy.all import *; sendp($multicast_pkt, iface='$nic_test', count=10)"
			fi
			sleep 60
			sync_set client trust_${trust_conf}_send_multicast_packets_finished
			#broadcast
			rlLog "Start broadcast packets test"
			sync_wait  client trust_${trust_conf}_send_broadcast_packets_start
			broadcast_pkt="Ether(src='${server_mac}', dst='FF:FF:FF:FF:FF:FF')/Dot1Q(vlan=100)/IP(src='172.30.${ipaddr}.2', dst='255.255.255.255')"
			if [ $(GetDistroRelease) = 8 ];then
				  /usr/libexec/platform-python -c  "from scapy.all import *; sendp($broadcast_pkt, iface='$nic_test', count=10 )"
			else
				python -c  "from scapy.all import *; sendp($broadcast_pkt, iface='$nic_test', count=10)"
			fi
			sleep 60
			sync_set client trust_${trust_conf}_send_broadcast_packets_finished
		done
		sync_wait client test_end
		#clear config
		rlRun "ip addr flush ${nic_test}"
		local origin_mac=$(ip link show $nic_test|grep link/ether|awk '{print $6}')
		rlLog "$nic_test origin mac $origin_mac,recover $nic_test mac address"
		ip link set $nic_test down
		sleep 1
		rlRun "ip link set $nic_test address $origin_mac"
		ip link set $nic_test up
		ip link set ${nic_test} promisc off
	else
		#Configure host mac and ip addr
		ip link set ${nic_test} up
		ip link set ${nic_test} promisc on
		ethtool --set-priv-flags ${nic_test} vf-true-promisc-support on
		ip addr add 172.30.${ipaddr}.1/24 dev ${nic_test}
		# create 2 vf interfaces and attach vf to 1 vm
		sriov_create_vfs ${nic_test} 0 2
		sriov_attach_vf_to_vm ${nic_test} 0 1 g1 ${vf_0_mac}
		sriov_attach_vf_to_vm ${nic_test} 0 2 g1 ${vf_1_mac}
		#Configure virtual machine
		cmd=(
			{set -x}
			{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \${NIC_TEST_0} up}
			{ip link set \${NIC_TEST_1} up}
			{ip addr flush \${NIC_TEST_0}}
			{ip addr flush \${NIC_TEST_1}}
			{ip addr add 172.30.${ipaddr}.3/24 dev \${NIC_TEST_0}}
			{ping -c 3 172.30.${ipaddr}.1}
			{ping -c 3 172.30.${ipaddr}.2}
			{set +x}
		)
		vmsh cmd_set g1 "${cmd[*]}"
		[ $? -ne 0 ]  && result=1 && rlFail "vf ping server/host ==> failed" && return $result
		sync_wait server configure_finished
		for trust_conf in {on,off}
		do
			#config vf "trust on/off" on host
			set -x
			ip link set ${nic_test} vf 0 trust ${trust_conf}
			ip link set ${nic_test} vf 1 trust ${trust_conf}
			set +x
			sleep 60  #need sometime to make the trust on/off valid
			local cmd=(
				{set -x}
				{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \${NIC_TEST_0} promisc on}
				{ip link set \${NIC_TEST_1} promisc on}
				{set +x}
			)
			vmsh cmd_set g1 "${cmd[*]}"
			rlLog "==================trust ${trust_conf}==================="
			rlLog "Start Unicast packets test"
			local cmd=(
				{set -x}
				{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{\[ -f unicast0.pcap \] \&\& rm -f unicast0.pcap}
				{\[ -f unicast1.pcap \] \&\& rm -f unicast1.pcap}
				{nohup tcpdump -i \$NIC_TEST_0 ip src 172.30.${ipaddr}.2 -enn -w unicast0.pcap  \&}
				{sleep 3}
				{nohup tcpdump -i \$NIC_TEST_1 ip src 172.30.${ipaddr}.2 -enn -w unicast1.pcap  \&}
				{sleep 3}
			)
			vmsh cmd_set g1 "${cmd[*]}"
			sync_set server trust_${trust_conf}_send_unicast_packets_start
			sync_wait server trust_${trust_conf}_send_unicast_packets_finished
			local cmd=(
				{ps -ef \| grep tcpdump}
				{pkill tcpdump}
				{sleep 5}
				{ll}
				{tcpdump -r unicast0.pcap -enn \| grep \"vlan 100\" }
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ]  && result=1 && rlFail "trust ${trust_conf}: No unicast packets captured on vf 0"
			if [ ${trust_conf} == "on" ]; then
				local cmd=(
				{tcpdump -r unicast1.pcap -enn \| grep \"vlan 100\" }
				)
				vmsh cmd_set g1 "${cmd[*]}"
				[ $? -ne 0 ]  && result=1 && rlFail "trust ${trust_conf}: No unicast packets captured on vf 1"
			else
				local cmd=(
				{tcpdump -r unicast1.pcap -enn \| grep \"vlan 100\" }
				)
				vmsh cmd_set g1 "${cmd[*]}"
				[ $? -eq 0 ]  && result=1 && rlFail "trust ${trust_conf}: Unicast packets captured on vf 1"
			fi
			rlLog "Start multicast packets test"

			local cmd=(
				{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{\[ -f multicast0.pcap \] \&\& rm -f multicast0.pcap}
				{\[ -f multicast0.pcap \] \&\& rm -f multicast0.pcap}
				{nohup tcpdump -i \$NIC_TEST_0 -enn ether multicast -w multicast0.pcap \&}
				{sleep 3}
				{nohup tcpdump -i \$NIC_TEST_1 -enn ether multicast -w multicast1.pcap \&}
				{sleep 3}
			)
			vmsh cmd_set g1 "${cmd[*]}"
			sync_set server trust_${trust_conf}_send_multicast_packets_start
			sync_wait server trust_${trust_conf}_send_multicast_packets_finished
			local cmd=(
				{ps -ef \| grep tcpdump}
				{pkill tcpdump}
				{sleep 5}
				{ll}
				{tcpdump -r multicast0.pcap -enn \| grep \"vlan 100\" }
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ]  && result=1 && rlFail "trust ${trust_conf}: No multicast packets captured on vf 0"
			local cmd=(
				{tcpdump -r multicast1.pcap -enn \| grep \"vlan 100\" }
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ]  && result=1 && rlFail "trust ${trust_conf}: No multicast packets captured on vf 1"
			rlLog "start broadcast packet test"
			local cmd=(
				{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{\[ -f broadcast0.pcap \] \&\& rm -f broadcast.pcap}
				{\[ -f broadcast0.pcap \] \&\& rm -f broadcast.pcap}
				{nohup tcpdump -i \$NIC_TEST_0 -enn ether broadcast -w broadcast0.pcap \&}
				{sleep 3}
				{nohup tcpdump -i \$NIC_TEST_1 -enn ether broadcast -w broadcast1.pcap \&}
				{sleep 3}
			)
			vmsh cmd_set g1 "${cmd[*]}"
			sync_set server trust_${trust_conf}_send_broadcast_packets_start
			sync_wait server trust_${trust_conf}_send_broadcast_packets_finished
			local cmd=(
				{ps -ef \| grep tcpdump}
				{pkill tcpdump}
				{sleep 5}
				{ll}
				{tcpdump -r broadcast0.pcap -enn \| grep \"vlan 100\" }
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ]  && result=1 && rlFail "trust ${trust_conf}: No broadcast packets captured on vf 0"
			local cmd=(
				{tcpdump -r broadcast1.pcap -enn \| grep \"vlan 100\" }
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ]  && result=1 && rlFail "trust ${trust_conf}: No broadcast packets captured on vf 1"
		done
		sync_set server test_end
		#clear conf
		local cmd=(
			{rm -f unicast*.pcap}
			{rm -f multicast*.pcap}
			{rm -f broadcast*.pcap}
		)
		vmsh cmd_set g1 "${cmd[*]}"
		sriov_detach_vf_from_vm  ${nic_test} 0 1 g1
		sriov_detach_vf_from_vm  ${nic_test} 0 2 g1
		sriov_remove_vfs ${nic_test} 0
		ip addr flush ${nic_test}
		ip link set ${nic_test} promisc off
		ethtool --set-priv-flags ${nic_test} vf-true-promisc-support off
		return $result
	fi
}

#
# buffer overflow and/or deadlock when VF has more than 32 multicast
#
sriov_test_bz1445814()
{
	log_header "sriov_test_bz1445814" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1445814_start
		sync_wait client test_bz1445814_end

		ip addr flush $nic_test
	else
		sync_wait server test_bz1445814_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1445814_end
			return 1
		fi

		vf_name=$(sriov_get_vf_iface $nic_test 0 1)
		for i in $(seq 2 50); do
			a="33:33:00:00:00:$(printf "%02x" $i)"
			rlLog $a
			ip ma add $a dev $vf_name
			if [ $? -ne 0 ];then
				let result+=1
				rlFail "failed: add ma $a error"
			fi
		done

		sriov_remove_vfs $nic_test 0

		sync_set server test_bz1445814_end
	fi

	return $result
}

# Description:
# 	Make sure the vf name in host don't change from distro to distro
#
# Test method:
#	0.this test need to use mysql database to store vf name
#	 	table desc:
#			   +--------+------------------+------+-----+---------+----------------+
#			   | Field  | Type			 | Null | Key | Default | Extra		  |
#			   +--------+------------------+------+-----+---------+----------------+
#			   | id	 | int(10) unsigned | NO   | PRI | NULL	| auto_increment |
#			   | distro | varchar(20)	  | YES  |	 | NULL	|				|
#			   | driver | varchar(20)	  | YES  |	 | NULL	|				|
#			   | host   | varchar(100)	 | YES  |	 | NULL	|				|
#			   | mac	| varchar(40)	  | YES  |	 | NULL	|				|
#			   | vfidx  | varchar(3)	   | YES  |	 | NULL	|				|
#			   | ifname | varchar(50)	  | YES  |	 | NULL	|				|
#			   +--------+------------------+------+-----+---------+----------------+
#	1.this test need to be run one time on a benchmark version to generate the benchmark vf name
#	2.this test will generate a vf and compare its name with the name stored in database
#		if can't find vf name from database(you have not generate the benchmark vf name), pass
#		if equal,						  						  pass
#		if not eauql,					  						  fail
#	3.use "distro,driver,host,mac,vfidx" to distinguish ifname in database
#	4.if have not added vfname related to current "distro,driver,host,mac,vfidx" to database, then will add it to database
#	5.drivers under testing:
#		cxgb4,be2net,bnx2x,mlx4_en,ixgbe,i40e,qlcnic,sfc,igb,mlx5_core,bnxt_en
#	6.some datas in my database:
#		+----+--------+---------+-----------------------------------------+-------------------+-------+-------------+
#		| id | distro | driver  | host									| mac			   | vfidx | ifname	  |
#		+----+--------+---------+-----------------------------------------+-------------------+-------+-------------+
#		| 16 | 7.4	| mlx4_en | hp-dl380pg8-08.rhts.eng.pek2.redhat.com | 00:02:c9:52:27:26 | 2	 | ens6f2	  |
#		| 17 | 7.4	| igb	 | hp-dl380g9-04.rhts.eng.pek2.redhat.com  | a0:36:9f:54:bb:2e | 2	 | enp136s16f4 |
#		| 18 | 7.4	| sfc	 | hp-dl388g8-22.rhts.eng.pek2.redhat.com  | 00:0f:53:21:68:30 | 2	 | ens3f3np0   |
#		| 19 | 7.4	| be2net  | hp-dl380pg8-15.rhts.eng.pek2.redhat.com | 00:90:fa:2a:65:82 | 2	 | enp7s4f1	|
#		| 20 | 7.4	| bnx2x   | hp-dl380pg8-08.rhts.eng.pek2.redhat.com | 00:0e:1e:50:f3:a0 | 2	 | enp7s1f1	|
#		| 21 | 7.4	| ixgbe   | hp-dl380g9-04.rhts.eng.pek2.redhat.com  | 00:1b:21:4a:fe:98 | 2	 | enp132s16f2 |
#		| 22 | 7.4	| i40e	| hp-dl380g9-04.rhts.eng.pek2.redhat.com  | 68:05:ca:2a:3a:30 | 2	 | enp5s2f1	|
#		| 23 | 7.4	| qlcnic  | hp-dl388g8-22.rhts.eng.pek2.redhat.com  | 00:0e:1e:14:9b:f0 | 2	 | enp36s2f1   |
#		| 24 | 7.4	| cxgb4   | hp-dl380pg8-15.rhts.eng.pek2.redhat.com | 00:07:43:2e:04:10 | 2	 | enp33s1f4   |
#		+----+--------+---------+-----------------------------------------+-------------------+-------+-------------+
#
sriov_test_vfname()
{
	log_header "sriov_test_vfname" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vfname_start
		sync_wait client test_vfname_end
	else
		sync_wait server test_vfname_start
		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vfname_end
			return 1
		fi

		local vf_name=$(sriov_get_vf_iface $nic_test 0 2)
		local RHEL_VERSION=$(cat /etc/redhat-release | grep [0-9].[0-9] -o)
		RHEL_VERSION_PRE=${RHEL_VERSION_PRE:-$(echo "$RHEL_VERSION-0.1" | bc -l)}
		#if (($(bc <<< "$RHEL_VERSION>=8")));then
		#		local dbtools=pymysql
		#		yum install -y python2-PyMySQL
		#else
		#		local dbtools=MySQLdb
		#		yum install -y  MySQL-python
		#fi

		nic_mac=$(ip link show $nic_test|grep ether|awk '{print $2}')
		local vf_name_old=$(./get_devname.py -s "driver='$NIC_DRIVER' and distro='$RHEL_VERSION_PRE' and host='$(hostname)' and mac='$nic_mac' and vfidx='2'")
		if [ "$vf_name_old" != "null" -a "$vf_name" != "$vf_name_old" ];then
			result=1
			rlFail "name check failed. current name:$vf_name, old name:$vf_name_old"
		fi
		rlLog "vf_name_old=$vf_name_old"
		./new_devname.py -V $RHEL_VERSION -D $NIC_DRIVER -H $(hostname) -M $nic_mac -I 2 -N $vf_name
		sriov_remove_vfs $nic_test 0

		sync_set server test_vfname_end
	fi

	return $result
}

sriov_test_hostdev_vmvf_remote()
{
	log_header "hostdev VMVF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_hostdev_vmvf_remote_start
		sync_wait client test_hostdev_vmvf_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_hostdev_vmvf_remote_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_hostdev_vmvf_remote_end
			return 1
		fi
		local old_sriov_use_hostdev=$SRIOV_USE_HOSTDEV
		SRIOV_USE_HOSTDEV="yes"
		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			result=$?

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0
		SRIOV_USE_HOSTDEV=$old_sriov_use_hostdev
		sync_set server test_hostdev_vmvf_remote_end
	fi

	return $result
}

#
# Guests using bonded VFs cannot communicate with each other when their active slave's VF interfaces are not from the same PF
#
sriov_test_bz1489964() {

	log_header "sriov_test_bz1489964" $result_file

	local result=0
	local test_name=sriov_test_bz1489964

	local server_ip4="192.100.${ipaddr}.1"
	local server_ip6="2021:db01:${ipaddr}::1"
	local client1_ip4="192.100.${ipaddr}.2"
	local client1_ip6="2021:db01:${ipaddr}::2"
	local client2_ip4="192.100.${ipaddr}.3"
	local client2_ip6="2021:db01:${ipaddr}::3"
	local server_vlanif_ip4="192.110.${ipaddr_vlan}.1"
	local server_vlanif_ip6="2021:db10:${ipaddr_vlan}::1"
	local client1_vlanif_ip4="192.110.${ipaddr_vlan}.2"
	local client1_vlanif_ip6="2021:db10:${ipaddr_vlan}::2"
	local client2_vlanif_ip4="192.110.${ipaddr_vlan}.3"
	local client2_vlanif_ip6="2021:db10:${ipaddr_vlan}::3"
	local ip4_mask_len=24
	local ip6_mask_len=64

	local vlan_id=3

	if i_am_server;then
		ip link set $nic_test up
		ip addr add ${server_ip4}/${ip4_mask_len} dev ${nic_test}
		ip addr add ${server_ip6}/${ip6_mask_len} dev ${nic_test}
		ip link add link $nic_test name ${nic_test}.${vlan_id} type vlan id $vlan_id
		ip link set ${nic_test}.${vlan_id} up
		ip addr add ${server_vlanif_ip4}/${ip4_mask_len} dev ${nic_test}.${vlan_id}
		ip addr add ${server_vlanif_ip6}/${ip6_mask_len} dev ${nic_test}.${vlan_id}
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end
		ip link del ${nic_test}.${vlan_id}
		ip addr flush dev $nic_test
	else

		sync_wait server ${test_name}_start
		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			sync_set server ${test_name}_end
			return 1
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		if ! sriov_create_vfs $iface1 0 4 || \
			! sriov_create_vfs $iface2 0 4;then
			let result++
			rlFail "${test_name} failed: can't create vfs."

		else
			ip link set $iface1 up
			ip link set $iface2 up
			sleep 10

			local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
			local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"
			local mac3="00:de:ad:$(printf %02x $ipaddr):01:03"
			local mac4="00:de:ad:$(printf %02x $ipaddr):01:04"

			ip link set $iface1 vf 0 trust on
			ip link set $iface1 vf 0 spoofchk on
			ip link set $iface1 vf 1 trust on
			ip link set $iface1 vf 1 spoofchk on
			ip link set $iface2 vf 2 trust on
			ip link set $iface2 vf 2 spoofchk on
			ip link set $iface2 vf 3 trust on
			ip link set $iface2 vf 3 spoofchk on

			if ! sriov_attach_vf_to_vm $iface1 0 1 $vm1 $mac1 || \
				! sriov_attach_vf_to_vm $iface2 0 3 $vm1 $mac2 || \
				! sriov_attach_vf_to_vm $iface1 0 2 $vm2 $mac3 || \
				! sriov_attach_vf_to_vm $iface2 0 4 $vm2 $mac4;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
			else
				vmsh run_cmd $vm1 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
				vmsh run_cmd $vm1 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
				vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
				vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface2) down"

				local cmd=(
					{modprobe -r bonding}
					{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
					{ip link set bond0 up}
					{ifenslave bond0 \$\(cat /tmp/testiface1\)}
					{ifenslave bond0 \$\(cat /tmp/testiface2\)}
					{ip addr add ${client1_ip4}/${ip4_mask_len} dev bond0}
					{ip addr add ${client1_ip6}/${ip6_mask_len} dev bond0}
					{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
					{ip link set bond0\.$vlan_id up}
					{ip addr add ${client1_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
					{ip addr add ${client1_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
					{ip link show}
					{ping ${server_vlanif_ip4} -c3}
					{ping ${server_ip4} -c3}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"
				if [ $? -ne 0 ];then
					{ rlFail "${test_name} failed: ping failed via vm1 bond0";let result++; }
				fi

				vmsh run_cmd $vm2 "echo \$(ip link | grep $mac3 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
				vmsh run_cmd $vm2 "echo \$(ip link | grep $mac4 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
				vmsh run_cmd $vm2 "ip link set \$(cat /tmp/testiface1) down"
				vmsh run_cmd $vm2 "ip link set \$(cat /tmp/testiface2) down"

				local cmd=(
					{modprobe -r bonding}
					{modprobe -v bonding mode=1 miimon=100 fail_over_mac=0 max_bonds=1}
					{ip link set bond0 up}
					{ifenslave bond0 \$\(cat /tmp/testiface1\)}
					{ifenslave bond0 \$\(cat /tmp/testiface2\)}
					{ip addr add ${client2_ip4}/${ip4_mask_len} dev bond0}
					{ip addr add ${client2_ip6}/${ip6_mask_len} dev bond0}
					{ip link add link bond0 name bond0\.$vlan_id type vlan id $vlan_id}
					{ip link set bond0\.$vlan_id up}
					{ip addr add ${client2_vlanif_ip4}/${ip4_mask_len} dev bond0\.$vlan_id}
					{ip addr add ${client2_vlanif_ip6}/${ip6_mask_len} dev bond0\.$vlan_id}
					{ip link show}
					{ping ${server_vlanif_ip4} -c3}
					{ping ${server_ip4} -c3}
				)
				vmsh cmd_set $vm2 "${cmd[*]}"
				if [ $? -ne 0 ];then
					{ rlFail "${test_name} failed: ping failed via vm2 bond0";let result++; }
				fi

				local cmd=(
					{ping ${client1_ip4} -c3}
					{ping6 ${client1_ip6} -c3}
					{ping ${client1_vlanif_ip4} -c3}
					{ping6 ${client1_vlanif_ip6} -c3}
				)
				vmsh cmd_set $vm2 "${cmd[*]}"
				if [ $? -ne 0 ];then
					{ rlFail "${test_name} failed: ping failed from vm2 to vm1";let result++; }
				fi

				vmsh run_cmd $vm1 "ip link set \$(cat /tmp/testiface1) down"
				vmsh run_cmd $vm2 "ip link set \$(cat /tmp/testiface2) down"
				sleep 2
				local cmd=(
					{ping ${client1_ip4} -c3}
					{ping6 ${client1_ip6} -c3}
					{ping ${client1_vlanif_ip4} -c3}
					{ping6 ${client1_vlanif_ip6} -c3}
				)
				vmsh cmd_set $vm2 "${cmd[*]}"
				if [ $? -ne 0 ];then
					{ rlFail "${test_name} failed: ping failed from vm2 to vm1 after link down if";let result++; }
				fi

			fi
			local cmd=(
				{ip link del bond0\.${vlan_id}}
				{ip link del bond0}
				{modprobe -r bonding}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			vmsh cmd_set $vm2 "${cmd[*]}"
			sriov_detach_vf_from_vm $iface1 0 1 $vm1
			sriov_detach_vf_from_vm $iface2 0 3 $vm1
			sriov_detach_vf_from_vm $iface1 0 2 $vm2
			sriov_detach_vf_from_vm $iface2 0 4 $vm2
			sriov_remove_vfs $iface1 0
			sriov_remove_vfs $iface2 0
		fi


		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result

}

sriov_test_spoofchk()
{
	log_header "test_spoofchk" $result_file

	local result=0

	ip link set $nic_test up
	local vf_mac="00:de:ad:$(printf %02x $ipaddr):01:01"
	local server_mac="00:de:ad:$(printf %02x $ipaddr):01:02"
	local spoof_mac="00:de:ad:$(printf %02x $ipaddr):01:03"

	if i_am_server; then
		local old_mac=$(ip link show $nic_test|grep link/ether|awk '{print $2}')
		rlLog "old mac $old_mac"
		ip addr flush $nic_test
		ip link set $nic_test down
		sleep 1
		ip link set $nic_test address $server_mac
		ip link set $nic_test up
		ip link show $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		[ -f spoof.cap ] && rm -f spoof.cap
		tcpdump -i $nic_test src 172.30.${ipaddr}.11 and dst 172.30.${ipaddr}.2 and dst port 9 -w spoof.cap &
		sync_set client test_spoofchk_start
		sync_wait client test_spoofchk_start1
		sync_set client test_spoofchk_on_non-vf_mac 180
		sync_wait client test_spoofchk_on_non-vf_mac 180
		pkill tcpdump
		sleep 1
		tcpdump -r spoof.cap -e -nn | grep "$spoof_mac > $server_mac"
		if [ $? -eq 0 ];then
			ip addr flush $nic_test
		fi
		sync_set client test_spoofchk_on_vf_mac_start 180
		sync_wait client test_spoofchk_on_vf_mac_start 180
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.4/24 dev $nic_test
		sync_set client test_spoofchk_on_vf_mac_check 180
		sync_wait client test_spoofchk_on_vf_mac_check 180
		tcpdump -r spoof.cap -e -nn | grep "${vf_mac} > ${server_mac}"
		if [ $? -ne 0 ];then
			ip addr flush $nic_test
		fi
		sync_set client test_spoofchk_pktgen_setip1 180
		sync_wait client test_spoofchk_pktgen_ping1 180
		ip addr flush $nic_test
		sleep 1
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		rm -f spoof.cap
		tcpdump -i $nic_test src 172.30.${ipaddr}.11 and dst 172.30.${ipaddr}.2 and dst port 9 -w spoof.cap &
		sync_set client test_spoofchk_pktgen_start2 180
		sync_wait client test_spoofchk_pktgen_end2 180
		pkill tcpdump
		sleep 1
		tcpdump -r spoof.cap -e -nn | grep "$spoof_mac > $server_mac"
		if [ $? -ne 0 ];then
			ip addr flush $nic_test
		fi
		sync_set client test_spoofchk_pktgen_setip2 180
		sync_wait client test_spoofchk_pktgen_ping2 180
		sync_set client test_spoofchk_end1 600
		sync_wait client test_spoofchk_end 600
		rlLog "ip link set $nic_test down"
		ip link set $nic_test down
		sleep 1
		rlLog "ip link set $nic_test address $old_mac"
		ip link set $nic_test address $old_mac
		rlLog "ip addr flush $nic_test"
		ip addr flush $nic_test
	else
		sync_wait server test_spoofchk_start
		sync_set server test_spoofchk_start1

		sriov_create_vfs $nic_test 0 1

		#ip link show $nic_test | grep "spoof checking off" && { result=1;echo "failed: vf default spoofchk off"; }

#		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $vf_mac; then
#			result=1
#		else
		ip link set $nic_test vf 0 spoofchk on
		##check whether support
		sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $vf_mac

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip addr flush \$NIC_TEST}
			{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
			{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
			{ip link show \$NIC_TEST}
			{ip addr show \$NIC_TEST}
			{timeout 60s bash -c \"until ping 172.30.${ipaddr}.2 -c 5\; do sleep 5\; done\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
			sync_wait server test_spoofchk_pktgen_start1 180
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{modprobe pktgen\;sleep 5\;}
			{echo \"rem_device_all\" \> /proc/net/pktgen/kpktgend_0}
			{echo \"add_device \$NIC_TEST\" \> /proc/net/pktgen/kpktgend_0}
			{echo \"dst_mac $server_mac\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_mac $spoof_mac\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"dst 172.30.${ipaddr}.2\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_min 172.30.${ipaddr}.11\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_max 172.30.${ipaddr}.11\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"pkt_size 512\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"count 100\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"start\" \> /proc/net/pktgen/pgctrl}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{modprobe pktgen\;sleep 5\;}
			{echo \"rem_device_all\" \> /proc/net/pktgen/kpktgend_0}
			{echo \"add_device \$NIC_TEST\" \> /proc/net/pktgen/kpktgend_0}
			{echo \"dst_mac $server_mac\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_mac ${vf_mac}\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"dst 172.30.${ipaddr}.2\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_min 172.30.${ipaddr}.11\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_max 172.30.${ipaddr}.11\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"pkt_size 512\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"count 100\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"start\" \> /proc/net/pktgen/pgctrl}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server test_spoofchk_on_non-vf_mac 180
		sync_wait server test_spoofchk_on_non-vf_mac 180
		local cmd=(
			{ping 172.30.${ipaddr}.2 -c 5}
			)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			result=1
			rlFail "failed: spoofchk on, received src mac=non-vf_mac packets"
		fi
		sync_set server test_spoofchk_on_vf_mac_start 180
		sync_wait server test_spoofchk_on_vf_mac_start 180
		sync_set server test_spoofchk_on_vf_mac_check 180
		sync_wait server test_spoofchk_on_vf_mac_check 180
		local cmd=(
			{ping 172.30.${ipaddr}.4 -c 5}
			)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			result=1
			rlFail "Failed, spoofchk on, src mac=vf_mac packets are not captured"
		fi
		sync_set server test_spoofchk_pkegen_ping1 180

		ip link set $nic_test vf 0 spoofchk off
			sync_wait server test_spoofchk_pktgen_start2 180
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{echo \"rem_device_all\" \> /proc/net/pktgen/kpktgend_0}
			{modprobe -r pktgen\;sleep 2\;}
			{modprobe pktgen\;sleep 5\;}
			{echo \"rem_device_all\" \> /proc/net/pktgen/kpktgend_0}
			{echo \"add_device \$NIC_TEST\" \> /proc/net/pktgen/kpktgend_0}
			{echo \"dst_mac $server_mac\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_mac $spoof_mac\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"dst 172.30.${ipaddr}.2\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_min 172.30.${ipaddr}.11\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"src_max 172.30.${ipaddr}.11\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"pkt_size 512\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"count 100\" \> /proc/net/pktgen/\$NIC_TEST}
			{echo \"start\" \> /proc/net/pktgen/pgctrl}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		sync_set server test_spoofchk_pktgen_end2 180
		sync_wait server test_spoofchk_pktgen_setip2 180
		local cmd=(
			{ping 172.30.${ipaddr}.2 -c 5}
			)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? -ne 0 ];then
			result=1
			rlFail "failed: spoofchk off, but server can't received packets"
		fi
		sync_set server test_spoofchk_pktgen_ping2 180
		local cmd=(
			{echo \"rem_device_all\" \> /proc/net/pktgen/kpktgend_0}
			{modprobe -r pktgen}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $nic_test 0 1 $vm1
#		fi

		sriov_remove_vfs $nic_test 0

		sync_wait server test_spoofchk_end1
		sync_set server test_spoofchk_end
	fi

	return $result
}

sriov_test_spoofchk_vlan()
{
	#Bug 2118135/Bug 2112335
	log_header "test_spoofchk_vlan" $result_file
	local result=0
	ip link set ${nic_test} up
	local vf_0_mac="00:de:ad:$(printf %02x $ipaddr):01:01"
	local vf_1_mac="00:de:ad:$(printf %02x $ipaddr):01:02"
	local server_mac="00:de:ad:$(printf %02x $ipaddr):01:21"
	if  i_am_server; then
		ip addr flush ${nic_test}
		ip link set ${nic_test} down
		sleep 1
		ip link set ${nic_test} address ${server_mac}
		ip link set ${nic_test} up
		ip link set ${nic_test} promisc on
		ip link show ${nic_test}
		sync_set  client configure_finished
		for spoof_conf in {on,off}
		do
			rlLog "=====Check spoofchk ${spoof_conf}====="
			ip addr add 172.30.${ipaddr}.2/24 dev ${nic_test}
			sleep 5
			[ -f spoof.cap ] && rm -f spoof.cap
			sync_wait client spoof_${spoof_conf}_capture_unicast_packet
			[ -f unicast.pcap ] && rm unicast.pcap
			tcpdump -i ${nic_test} -enn  -w unicast.pcap &
			sync_set client spoof_${spoof_conf}_stop_capture_unicast_packet
			pkill -9 tcpdump
			rlRun "tcpdump -r unicast.pcap -e -nn | grep 'vlan 100'"
			[ $? -ne 0 ] &&  ip addr flush ${nic_test}
			sync_wait client spoof_${spoof_conf}_unicast_get_return_from_server
			rlLog "spoofchk ${spoof_conf}: multicast test start"
			[ -f multicast.pcap ] && rm multicast.pcap
			ip addr add 172.30.${ipaddr}.2/24 dev ${nic_test}
			sync_set client spoof_${spoof_conf}_capture_multicast_packet
			tcpdump -i ${nic_test} -enn  -w multicast.pcap &
			sync_wait client spoof_${spoof_conf}_stop_capture_multicast_packet
			pkill -9 tcpdump
			rlRun "tcpdump -r multicast.pcap -enn | grep 'vlan 100'"
			[ $? -ne 0 ] &&  ip addr flush ${nic_test}
			sync_set client spoof_${spoof_conf}_multicast_get_return_from_server
			rlLog "spoofchk ${spoof_conf}: broadcast test start"
			[ -f broadcast.pcap ] && rm broadcast.pcap
			ip addr add 172.30.${ipaddr}.2/24 dev ${nic_test}
			sync_wait client spoof_${spoof_conf}_capture_broadcast_packet
			tcpdump -i ${nic_test} -enn  -w broadcast.pcap  &
			sync_set client spoof_${spoof_conf}_stop_capture_broadcast_packet
			pkill -9 tcpdump
			rlRun "tcpdump -r broadcast.pcap -enn | grep 'vlan 100'"
			[ $? -ne 0 ] &&  ip addr flush ${nic_test}
			sync_wait client spoof_${spoof_conf}_broadcast_get_return_from_server
		done
		sync_set  client test_end
		#clear config
		ip addr flush ${nic_test}
		ip link set ${nic_test} promisc off
		set +x
	else
	#Configure host mac and ip addr
		ip link set ${nic_test} promisc on
		ethtool --set-priv-flags ${nic_test} vf-true-promisc-support on
		ip addr add 172.30.${ipaddr}.1/24 dev ${nic_test}
		# create 2 vf interfaces and attach vf to 1 vm
		sriov_create_vfs ${nic_test} 0 2
		sriov_attach_vf_to_vm ${nic_test} 0 1 g1 ${vf_0_mac}
		sriov_attach_vf_to_vm ${nic_test} 0 2 g1 ${vf_1_mac}
		#install scapy on vm
		cmd=(
			{source /mnt/tests/kernel/networking/common/install.sh}
			{scapy_install}
		)
		vmsh cmd_set g1 "${cmd[*]}"
		#Configure virtual machine
		cmd=(
			{set -x}
			{ip link show}
			{systemctl stop NetworkManager}
			{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr flush \${NIC_TEST_0}}
			{ip addr flush \${NIC_TEST_1}}
			{ip addr add 172.30.${ipaddr}.3/24 dev \${NIC_TEST_0}}
			{ip link set \${NIC_TEST_0} up}
			{ip link set \${NIC_TEST_1} up}
			{ip link set \${NIC_TEST_1} promisc on}
			{set +x}
		)
		vmsh cmd_set g1 "${cmd[*]}"
		[ $? -ne 0 ]  && result=1 && rlFail "vf ping server/host ==> failed"
		sync_wait server configure_finished
		cmd=(
			{ping -c 3 172.30.${ipaddr}.1}
			{ping -c 3 172.30.${ipaddr}.2}
		)
		vmsh cmd_set g1 "${cmd[*]}"
		# Send packet from g1 vf0
		for spoof_conf in {on,off}
		do
			#config vf "spoof on" on host
			ip link set ${nic_test} vf 0 spoofchk ${spoof_conf}
			ip link set ${nic_test} vf 1 spoofchk ${spoof_conf}
			rlLog "spoofchk ${spoof_conf}: unicast test start"
			unicast_pkt="Ether(src='${vf_0_mac}', dst='${server_mac}')/Dot1Q(vlan=100)"
			if [ $(GetDistroRelease) = 8 ];then
				cmd=(
					{set -x}
					{NIC_TEST_0=\$\(ip link show \| grep \'${vf_0_mac}\' -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60 tcpdump -i \${NIC_TEST_1} -enn -w unicast.pcap \&}
					{/usr/libexec/platform-python -c  \"from scapy.all import *\; sendp\(${unicast_pkt},  iface=\'\"\${NIC_TEST_0}\"\', count=5\)\"}
					{bash -c \"sleep 60\"}
					{tcpdump -r unicast.pcap -enn \| grep \"vlan 100\"}
					{set +x}
				)
			else
				cmd=(
					{set -x}
					{NIC_TEST_0=\$\(ip link show \| grep \'${vf_0_mac}\' -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60 tcpdump -i \${NIC_TEST_1} -enn -w unicast.pcap \&}
					{python -c  \"from scapy.all import *\; sendp\(${unicast_pkt},  iface=\'\"\${NIC_TEST_0}\"\', count=5\)\"}
					{bash -c \"sleep 60\"}
					{tcpdump -r unicast.pcap -enn \| grep \"vlan 100\"}
					{set +x}
				)
			fi
			sync_set server spoof_${spoof_conf}_capture_unicast_packet
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -eq 0 ] && result=1 && rlFail "spoofchk ${spoof_conf} unicast Failed, there should be no packets captured on vf 1"
			sync_wait server spoof_${spoof_conf}_stop_capture_unicast_packet

			cmd=(
				{ping -c 3 172.30.${ipaddr}.2}
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ] && result=1 && rlFail "spoofchk ${spoof_conf} unicast Failed, server did not captured unicast packets"
			sync_set server spoof_${spoof_conf}_unicast_get_return_from_server
			rlLog "spoofchk ${spoof_conf}: multicast test start"
			multicast_pkt="Ether(src='${vf_0_mac}', dst='01:00:5e:00:00:01')/Dot1Q(vlan=100)"
			if [ $(GetDistroRelease) = 8 ];then
				cmd=(
					{set -x}
					{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60 tcpdump -i \${NIC_TEST_1} -enn  -w multicast.pcap \&}
					{/usr/libexec/platform-python -c  \"from scapy.all import *\; sendp\(${multicast_pkt}, iface=\'\"\${NIC_TEST_0}\"\', count=5\)\"}
					{bash -c \"sleep 60\"}
					{tcpdump -r multicast.pcap -enn \| grep \"vlan 100\"}
					{set +x}
				)
			else
				cmd=(
					{set -x}
					{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60 tcpdump -i \${NIC_TEST_1} -enn  -w multicast.pcap \&}
					{python -c  \"from scapy.all import *\; sendp\(${multicast_pkt}, iface=\'\"\${NIC_TEST_0}\"\', count=5\)\"}
					{bash -c \"sleep 60\"}
					{tcpdump -r multicast.pcap -enn \| grep \"vlan 100\"}
					{set +x}
				)
			fi
			sync_wait server spoof_${spoof_conf}_capture_multicast_packet
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ] && result=1 && rlFail "spoofchk ${spoof_conf} multicast Failed, there should be  packets captured on vf 1"
			sync_set server  spoof_${spoof_conf}_stop_capture_multicast_packet

			cmd=(
				{ping -c 3 172.30.${ipaddr}.2}
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ] && result=1 && rlFail "spoofchk ${spoof_conf} multicast Failed, server did not captured multicast packets"
			sync_wait server spoof_${spoof_conf}_multicast_get_return_from_server
			rlLog "spoofchk ${spoof_conf}: broadcast test start"
			broadcast_pkt="Ether(src='${vf_0_mac}', dst='FF:FF:FF:FF:FF:FF')/Dot1Q(vlan=100)"
			if [ $(GetDistroRelease) = 8 ];then
				cmd=(
					{set -x}
					{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60 tcpdump -i \${NIC_TEST_1} -enn  -w broadcast.pcap \&}
					{/usr/libexec/platform-python -c  \"from scapy.all import *\; sendp\(${broadcast_pkt}, iface=\'\"\${NIC_TEST_0}\"\', count=5\)\"}
					{bash -c \"sleep 60\"}
					{tcpdump -r broadcast.pcap -enn \| grep \"vlan 100\"}
					{set +x}
				)
			else
				cmd=(
					{set -x}
					{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{export NIC_TEST_1=\$\(ip link show \| grep ${vf_1_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{timeout 60 tcpdump -i \${NIC_TEST_1} -enn  -w broadcast.pcap \&}
					{python -c  \"from scapy.all import *\; sendp\(${broadcast_pkt}, iface=\'\"\${NIC_TEST_0}\"\', count=5\)\"}
					{bash -c \"sleep 60\"}
					{tcpdump -r broadcast.pcap -enn \| grep \"vlan 100\"}
					{set +x}
				)
			fi
			sync_set server spoof_${spoof_conf}_capture_broadcast_packet
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ] && result=1 && rlFail "spoofchk ${spoof_conf} broadcast Failed, there should be  packets captured on vf 1"
			sync_wait server spoof_${spoof_conf}_stop_capture_broadcast_packet
			cmd=(
				{ping -c 3 172.30.${ipaddr}.2}
			)
			vmsh cmd_set g1 "${cmd[*]}"
			[ $? -ne 0 ] && result=1 && rlFail "spoofchk ${spoof_conf} broadcast Failed, server did not captured broadcast packets"
			sync_set server spoof_${spoof_conf}_broadcast_get_return_from_server
		done
		sync_wait server test_end
		#clear conf
		cmds=(
			{export NIC_TEST_0=\$\(ip link show \| grep ${vf_0_mac} -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr flush \${NIC_TEST_0}}
			{systemctl start NetworkManager}
		)
		vmsh cmd_set g1 "${cmds[*]}"
		sriov_detach_vf_from_vm  ${nic_test} 0 1 g1
		sriov_detach_vf_from_vm  ${nic_test} 0 2 g1
		sriov_remove_vfs ${nic_test} 0
		ip addr flush ${nic_test}
		ip link set ${nic_test} promisc off
		ethtool --set-priv-flags ${nic_test} vf-true-promisc-support off
		return $result
	fi
}

# guest VM unable to communicate when VFs are defined on hosts PF
#
sriov_test_bz1493953()
{
	log_header "sriov_test_bz1493953" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_bz1493953_start
		sync_wait client test_bz1493953_end

		ip addr flush $nic_test
	else
		sync_wait server test_bz1493953_start

		ip link add br0 type bridge
		ip link set br0 up
		#get the corresponding vnet port
		#vnetport=$(ip link show | grep vnet | grep virbr0 | awk '{ print $2 }' | sed 's/://g' | head -n1)
		rlLog "virsh dumpxml ${vm1}| grep -C 5 ${mac4vm1} | grep vnet | awk -F \"dev='\" '{print $2}' | sed \"s/'\/>//g\""
		vnetport=$(virsh dumpxml ${vm1}| grep -C 5 ${mac4vm1} | grep vnet | awk -F "dev='" '{print $2}' | sed "s/'\/>//g")
		rlLog "vnet $vnetport"
		if (($rhel_version <= 6)); then
			#brctl delif virbr0 vnet0
			#brctl addif br0 vnet0
			#brctl addif br0 $nic_test
			ip link set dev $vnetport nomaster
			ip link set dev $vnetport master br0
			ip link set dev $nic_test master br0
		else
			ip link set $nic_test master br0
			ip link set $vnetport master br0
			ip link show
		fi

		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1493953_end
			ip link del br0
			return 1
		fi

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
			{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		local cmd=(
			{timeout 60s bash -c \"until ping -c3 172.30.${ipaddr}.2\; do sleep 5\; done\"}
			{timeout 60s bash -c \"until ping6 -c3 2021:db8:${ipaddr}::2\; do sleep 5\; done\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		result=$?

		if (($rhel_version <= 6)); then
			#brctl delif br0 vnet0
			#brctl addif br0 virbr0
			#brctl delif br0 $nic_test
			ip link set dev $vnetport nomaster
			ip link set dev $vnetport master virbr0
			ip link set dev $nic_test nomaster

		else
			ip link set $vnetport master virbr0
			ip link set $nic_test nomaster
		fi
		ip link del br0
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr del 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
			{ip addr del 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_remove_vfs $nic_test 0

		sync_set server test_bz1493953_end
	fi

	return $result
}

#
#  ixgbevf takes a long time to update net.ipv6.conf.all.forwarding=1
#
sriov_test_bz1483396()
{
	log_header "sriov_test_bz1483396" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		sync_set client test_bz1483396_start
		sync_wait client test_bz1483396_end
	else
		sync_wait server test_bz1483396_start

		if ! sriov_create_vfs $nic_test 0 1; then
			sync_set server test_bz1483396_end
			ip link del br0
			return 1
		fi
		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		ip link set $vf down
		ip link set $vf name vf0
		ip link set vf0 up
		ip link add link vf0 name vf0.100 type vlan proto 802.1ad id 100
		ip link set dev vf0.100 up
		for NUM in {1..2048}; do
			ip link add link vf0.100 name vf0.100.$NUM type vlan proto 802.1q id $NUM
			ip link set dev vf0.100.$NUM up
		done
		#will chech dmesg with param "--param=SET_DMESG_CHECK_KEY=yes" for every Task testing
		#dmesg -C;dmesg -c
		time sysctl -w net.ipv6.conf.all.forwarding=1
		dmesg|grep "BUG: soft lockup" && { result=1; rlFail "failed:soft lockup occur"; }
		#dmesg -C;dmesg -c
		time sysctl -w net.ipv6.conf.all.forwarding=0
		dmesg|grep "BUG: soft lockup" && { result=1; rlFail "failed:soft lockup occur"; }

		ip link del vf0.100
		sriov_remove_vfs $nic_test 0

		sync_set server test_bz1483396_end
		fi

	return $result
}

sriov_test_vmvf_multicast()
{
	log_header "VMVF multicast" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		ping 224.10.10.10 -I $nic_test &
		sync_set client test_vmvf_multicast_start
		sync_wait client test_vmvf_multicast_end
		pkill ping

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_multicast_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_multicast_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
				{cp -u /mnt/tests/kernel/networking/common/src/mtools/join_group.c ./}
								{gcc -o /usr/local/bin/join_group join_group.c}
				{join_group -f 4 -g 224.10.10.10 -i \$NIC_TEST \&}
				{ip maddr sh \$NIC_TEST \| grep 224.10.10.10}
				{ip maddr sh \$NIC_TEST \| grep 01:00:5e:0a:0a:0a}
				{test \"\$\(tshark -a duration:30 -nVpq -i \$NIC_TEST -f \"dst host 224.10.10.10\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'224.10.10.10\'}
				{pkill join_group}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				result=1
				rlFail "failed: join multicast group fail"
			fi


			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip maddr sh \$NIC_TEST \| grep 224.10.10.10}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -eq 0 ];then
				result=1
				rlFail "failed: leave multicast group fail, still see 224.10.10.10 in ip maddr"
			fi

			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip maddr sh \$NIC_TEST \| grep 01:00:5e:0a:0a:0a}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -eq 0 ];then
				result=1
				rlFail "failed: leave multicast group fail, still see 01:00:5e:0a:0a:0a in ip maddr"
			fi

			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{test \"\$\(tshark -a duration:30 -nVpq -i \$NIC_TEST -f \"dst host 224.10.10.10\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'224.10.10.10\'}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -eq 0 ];then
				#result=1
				rlFail "warning: leave multicast group fail, still receiving multicast packet"
			fi

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_multicast_end
	fi

	return $result
}

sriov_test_vmvf_reg_ureg_multicast_addr()
{
	log_header "reg_ureg_multicast_addr" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		ping 224.10.10.10 -I $nic_test &
		sync_set client test_vmvf_reg_ureg_multicast_addr_start
		sync_wait client test_vmvf_reg_ureg_multicast_addr_end
		pkill ping

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_multicast_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_reg_ureg_multicast_addr_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
			result=1
		else
			vmsh run_cmd $vm1 "dmesg -c > /dev/null 2>&1;dmesg -C > /dev/null 2>&1"
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
				{cp -u /mnt/tests/kernel/networking/common/src/mtools/join_group.c ./}
				{gcc -o /usr/local/bin/join_group join_group.c}
				{join_group -f 4 -g 224.10.10.10 -i \$NIC_TEST \&}
				{test \"\$\(tshark -a duration:30 -nVpq -i \$NIC_TEST -f \"dst host 224.10.10.10\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'224.10.10.10\'}
				{for i in `seq 0 100`\;do join_group -f 4 -g 224.10.10.10 -i \$NIC_TEST \& sleep 1\; ip maddr sh \$NIC_TEST \| grep 224.10.10.10\; pkill join_group\; sleep 1\; done\;}
				{join_group -f 4 -g 224.10.10.10 -i \$NIC_TEST \&}
				{ip maddr sh \$NIC_TEST \| grep 224.10.10.10}
				{ip maddr sh \$NIC_TEST \| grep 01:00:5e:0a:0a:0a}
				{test \"\$\(tshark -a duration:30 -nVpq -i \$NIC_TEST -f \"dst host 224.10.10.10\" -c1 -T fields -e ip.dst 2\>/dev/null\)\" = \'224.10.10.10\'}
				{pkill join_group}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				result=1
				rlFail "failed: join multicast group fail"
			fi


			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip maddr sh \$NIC_TEST \| grep 224.10.10.10}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -eq 0 ];then
				result=1
				rlFail "failed: leave multicast group fail, still see 224.10.10.10 in ip maddr"
			fi

			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip maddr sh \$NIC_TEST \| grep 01:00:5e:0a:0a:0a}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -eq 0 ];then
				result=1
				rlFail "failed: leave multicast group fail, still see 01:00:5e:0a:0a:0a in ip maddr"
			fi

			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{dmesg \| grep -i \"\$NIC_TEST.*link.*down\"}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -eq 0 ];then
				result=1
				rlFail "failed: link down detected"
			fi

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_reg_ureg_multicast_addr_end
	fi

	return $result
}

#
#topo of sriov_test_vmpf_vmvf_remote
#+------------------------------------------+
#|										  |
#|   +--------+		+--------+		   |
#|   |  VM1   |		|  VM2   |		   |
#|   +--------+		+--------+		   |
#|	   |virtual		   |			   |
#|	   |port			  |			   |
#|   +--------+			 |			   |
#|   | bridge |			 |			   |
#|   | virbr1 |			 |			   |
#|   +--------+			 |			   |
#|		  |			   |			   |
#|		  |			   |			   |
#|		  +--PF--+----VF--+			   |
#|				 |						|
#|		   +---------+					|
#|		   |bnx2x NIC|			 client |
#+------------------------------------------+
#				|
#				|
#			 server

sriov_test_vmpf_vmvf_remote()
{
	log_header "VMPF_VMVF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmpf_vmvf_remote_start
		sync_wait client test_vmpf_vmvf_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmpf_vmvf_remote_start

		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		ip link set dev $nic_test master virbr1
		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmpf_vmvf_remote_end
			return 1
		fi

		if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm2 $mac; then
			result=1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
				{ip a}
			)
			vmsh cmd_set $vm2 "${cmd[*]}"

			#ip link set $nic_test master virbr1
			#brctl addif virbr1 $nic_test
			#ip link set dev $nic_test master virbr1
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac4vm1if2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.12/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::12/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
				{ip a}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			do_vm_netperf $vm2 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			result=$?
			do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			let result+=$?
			#do_vm_netperf $vm1 172.30.${ipaddr}.11 2021:db8:${ipaddr}::11 $result_file
			#let result+=$?

			sriov_detach_vf_from_vm $nic_test 0 1 $vm2
			#ip link set $nic_test nomaster
			#brctl delif virbr1 $nic_test
			#ip link set dev $nic_test nomaster
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac4vm1if2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip addr flush \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
		fi

		sriov_remove_vfs $nic_test 0
		ip link set dev $nic_test nomaster

		sync_set server test_vmpf_vmvf_remote_end
	fi

	return $result
}


#topo of sriov_test_vmpfbond_vmvfbond_remote
#+----------------------------------------------------+
#|													|
#|   +--------+		+--------+			  client |
#|   |  VM1   |		|  VM2   |					 |
#|   |		|		|vf bond |					 |
#|   +--------+		+--------+					 |
#|	   |virtual	   |	  |					  |
#|	   |port		  |	  |					  |
#|   +--------+		 |	  |					  |
#|   | bridge |	   vf|	  |vf					|
#|   | virbr1 |		 |	  |					  |
#|   +--------+		 |	  |					  |
#|		  |		   |	  +-----------------+	|
#|		  |   bond	|						|	|
#|		  +-----------|-------------------+	|	|
#|		   pf|		|				 pf|	|	|
#|		   +-----------+			   +---------+  |
#|		   |	 NIC   |			   |   NIC   |  |
#+----------------------------------------------------+
#				|
#				|
#			  server

sriov_test_vmpfbond_vmvfbond_remote()
{
	log_header "VMPFBOND_VMVFBOND <---> REMOTE" $result_file

	local result=0
	local test_name=sriov_test_vmpfbond_vmvfbond_remote

	local server_ip4="192.100.${ipaddr}.1"
	local server_ip6="2021:db02:${ipaddr}::1"
	local client1_ip4="192.100.${ipaddr}.2"
	local client1_ip6="2021:db02:${ipaddr}::2"
	local client2_ip4="192.100.${ipaddr}.3"
	local client2_ip6="2021:db02:${ipaddr}::3"
	local ip4_mask_len=24
	local ip6_mask_len=64

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test

		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end

		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_start

		OLD_NIC_NUM=$NIC_NUM
		OLD_NIC_DRIVER=$NIC_DRIVER
		OLD_NIC_MODEL=$NIC_MODEL
		OLD_NIC_SPEED=$NIC_SPEED

		local NIC_NUM=2
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		if [ $? -ne 0 ];then
			rlFail "$test_name get required_iface failed."
			let result++
		fi
		iface1=$(echo $test_iface | awk '{print $1}')
		iface2=$(echo $test_iface | awk '{print $2}')
		rlLog "test_ifaces:$iface1,$iface2"

		ip link set $iface1 up
		ip link set $iface2 up
		if ! sriov_create_vfs $iface1 0 2 || \
			! sriov_create_vfs $iface2 0 2;then
				let result++
				rlFail "${test_name} failed: can't create vfs."
		fi

		modprobe -rv bonding
		modprobe -v bonding mode=1 fail_over_mac=1 miimon=100 max_bonds=1
		ip link set bond0 up
		ifenslave bond0 $iface1 $iface2
		#brctl addif virbr1 bond0
		ip link set dev bond0 master virbr1
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1if2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip addr flush \$NIC_TEST}
			{ip addr add $client1_ip4/$ip4_mask_len dev \$NIC_TEST}
			{ip addr add $client1_ip6/$ip6_mask_len dev \$NIC_TEST}
			{ip link show \$NIC_TEST}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		ip link set $iface1 vf 0 trust on
		ip link set $iface1 vf 0 spoofchk off
		ip link set $iface2 vf 1 trust on
		ip link set $iface2 vf 1 spoofchk off

		if ! sriov_attach_vf_to_vm $iface1 0 1 $vm2 $mac1 || \
			! sriov_attach_vf_to_vm $iface2 0 2 $vm2 $mac2;then
				let result++
				rlFail "${test_name} failed: can't attach vf to vm."
		fi
		vmsh run_cmd $vm2 "echo \$(ip link | grep $mac1 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface1"
		vmsh run_cmd $vm2 "echo \$(ip link | grep $mac2 -B1 | head -n1 | awk '{print \$2}'	  | sed 's/://g') | tee /tmp/testiface2"
		vmsh run_cmd $vm2 "ip link set \$(cat /tmp/testiface1) down"
		vmsh run_cmd $vm2 "ip link set \$(cat /tmp/testiface2) down"

		local cmd=(
				{modprobe -r bonding}
				{modprobe -v bonding mode=1 miimon=100 fail_over_mac=1 max_bonds=1}
				{ip link set bond0 up}
				{ifenslave bond0 \$\(cat /tmp/testiface1\)}
				{ifenslave bond0 \$\(cat /tmp/testiface2\)}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"
		if [ $? -ne 0 ];then
			{ rlFail "${test_name} failed: fail_over_mac=1, ifenslave failed";let result++; }
		fi
		local cmd=(
			{ip addr add ${client2_ip4}/${ip4_mask_len} dev bond0}
			{ip addr add ${client2_ip6}/${ip6_mask_len} dev bond0}
			{ip addr show}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"

		do_vm_netperf $vm2 $server_ip4 $server_ip6 $result_file
		result=$?
		do_vm_netperf $vm1 $server_ip4 $server_ip6 $result_file
		let result+=$?
		#do_vm_netperf $vm1 ${client2_ip4} ${client2_ip6} $result_file
		#let result+=$?

		local cmd=(
			{ip link del bond0}
			{modprobe -r bonding}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac4vm1if2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip addr flush \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"

		sriov_detach_vf_from_vm $iface1 0 1 $vm2
		sriov_detach_vf_from_vm $iface2 0 2 $vm2
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0

		#brctl delif virbr0 bond0
		ip link set dev bond0 nomaster
		modprobe -rv bonding

		NIC_NUM=$OLD_NIC_NUM
		NIC_DRIVER=$OLD_NIC_DRIVER
		NIC_MODEL=$OLD_NIC_MODEL
		NIC_SPEED=$OLD_NIC_SPEED

		sync_set server ${test_name}_end
	fi

	return $result
}

sriov_test_attach_method_is_forward_hostdev()
{
	log_header "sriov_test_attach_method_is_forward_hostdev" $result_file

	local result=0
	local test_name=sriov_test_attach_method_is_forward_hostdev

	local server_ip4="192.100.${ipaddr}.1"
	local server_ip6="2021:db02:${ipaddr}::1"
	local client1_ip4="192.100.${ipaddr}.2"
	local client1_ip6="2021:db02:${ipaddr}::2"
	local client2_ip4="192.100.${ipaddr}.3"
	local client2_ip6="2021:db02:${ipaddr}::3"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local vid=3
	ip link set $nic_test up

	if i_am_server; then
		ip link set $nic_test up
		sleep 1
		ip addr flush $nic_test
		sleep 1
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		sleep 1
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		sleep 1
		ip a

		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end

		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_start
	modprobe vfio-pci
		if ! sriov_create_vfs $nic_test 0 2;then
			let result++
			rlFail "${test_name} failed: can't create vfs."

		fi

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		local vf1_bus_info=$(sriov_get_vf_bus_info $nic_test 0 1)
		local vf1_domain=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $1}')
		local vf1_bus=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $2}')
		local vf1_slot=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $3}')
		local vf1_function=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $4}')

		local vf2_bus_info=$(sriov_get_vf_bus_info $nic_test 0 2)
		local vf2_domain=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $1}')
		local vf2_bus=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $2}')
		local vf2_slot=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $3}')
		local vf2_function=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $4}')

		cat <<-EOF > /usr/share/libvirt/networks/forward_hostdev.xml
			<network>
				<name>forward_hostdev</name>
				<forward mode='hostdev' managed='yes'>
					<driver name='vfio'/>
					<address type='pci' domain='0x$vf1_domain' bus='0x$vf1_bus' slot='0x$vf1_slot' function='0x$vf1_function'/>
					<address type='pci' domain='0x$vf2_domain' bus='0x$vf2_bus' slot='0x$vf2_slot' function='0x$vf2_function'/>
				</forward>
			</network>
		EOF
		cat <<-EOF > vf1.xml
			<interface type='network'>
				<source network='forward_hostdev'/>
				<target dev='vf1'/>
				<mac address='$mac1'/>
			</interface>
		EOF
		cat <<-EOF > vf2.xml
			<interface type='network'>
				<source network='forward_hostdev'/>
				<target dev='vf2'/>
				<mac address='$mac2'/>
			</interface>
		EOF
		cat /usr/share/libvirt/networks/forward_hostdev.xml
		cat vf1.xml
		cat vf2.xml
		virsh net-define /usr/share/libvirt/networks/forward_hostdev.xml
		virsh net-start forward_hostdev
		sleep 5
		if ! virsh attach-device $vm1 vf1.xml || \
			! virsh attach-device $vm2 vf2.xml;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{sleep 1}
			{ip addr flush \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client1_ip4}/${ip4_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client1_ip6}/${ip6_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip a}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{sleep 1}
			{ip addr flush \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client2_ip4}/${ip4_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client2_ip6}/${ip6_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip a}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"

		#do_vm_netperf $vm2 $server_ip4 $server_ip6 $result_file
		#do_vm_netperf $vm1 $server_ip4 $server_ip6 $result_file
		#do_vm_netperf $vm1 ${client2_ip4} ${client2_ip6} $result_file
		#do_vm_netperf $vm2 $server_vlan_ip4 $server_vlan_ip6 $result_file
		#do_vm_netperf $vm1 $server_vlan_ip4 $server_vlan_ip6 $result_file
		#do_vm_netperf $vm1 ${client2_vlan_ip4} ${client2_vlan_ip6} $result_file
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			#{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{echo \$NIC_TEST}
			{ip link show}
			{timeout 40s bash -c \"until ping -I \$NIC_TEST -c3 ${server_ip4}\; do sleep 5\; done\"}
			{timeout 40s bash -c \"until ping6 -I \$NIC_TEST -c3 ${server_ip6}\; do sleep 5\; done\"}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		let result+=$?
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{echo \$NIC_TEST}
			{ip link show}
			{timeout 40s bash -c \"until ping -I \$NIC_TEST -c3 ${server_ip4}\; do sleep 5\; done\"}
			{timeout 40s bash -c \"until ping6 -I \$NIC_TEST -c3 ${server_ip6}\; do sleep 5\; done\"}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"
		let result+=$?
#		vmsh run_cmd $vm1 "timeout 40s bash -c \"until ping -c3 ${server_ip4}; do sleep 5; done\""
#		result=$?
#		vmsh run_cmd $vm1 "timeout 40s bash -c \"until ping6 -c3 ${server_ip6}; do sleep 5; done\""
#		let result+=$?
#		vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping -c3 ${server_ip4}; do sleep 5; done\""
#		let result+=$?
#		vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping6 -c3 ${server_ip6}; do sleep 5; done\""
#		let result+=$?

#		vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping -c3 ${client1_ip4}; do sleep 5; done\""
#		result=$?
#		vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping6 -c3 ${client1_ip6}; do sleep 5; done\""
#		let result+=$?
		if [[ $ENABLE_RT_KERNEL != "yes" ]]; then
			virsh detach-device g1 vf1.xml || { rlFail "detach vf1 failed"; let result++; }
			sleep 3
			virsh detach-device g2 vf2.xml || { rlFail "detach vf2 failed"; let result++; }
			sleep 3
		else
			virsh detach-device g1 vf1.xml --config
			virsh detach-device g2 vf2.xml --config
			virsh shutdown g1
			virsh shutdown g2
			sleep 10
			virsh start g1
			virsh start g2
			sleep 10
			local vm1_status=$(virsh list --all | grep g1 |  awk '{print $3,$4}')
			local vm2_status=$(virsh list --all | grep g2 |  awk '{print $3,$4}')
			rlLog "current g1 and g2 guest status is ${vm1_status}, ${vm2_status}"
		fi
		virsh net-destroy forward_hostdev
		virsh net-undefine forward_hostdev
		sriov_remove_vfs $nic_test 0 || { rlFail "remove vf failed"; let result++; }

		sync_set server ${test_name}_end
	fi

	return $result
}
sriov_test_attach_method_is_forward_hostdev_vlan()
{
	log_header "sriov_test_attach_method_is_forward_hostdev_vlan" $result_file

	local result=0
	local test_name=sriov_test_attach_method_is_forward_hostdev_vlan

	local server_ip4="192.120.${ipaddr}.10"
	local server_ip6="2021:db22:${ipaddr}::10"
	local server_vlan_ip4="192.120.${ipaddr}.1"
	local server_vlan_ip6="2021:db22:${ipaddr}::1"
	local client1_vlan_ip4="192.120.${ipaddr}.2"
	local client1_vlan_ip6="2021:db22:${ipaddr}::2"
	local client2_vlan_ip4="192.120.${ipaddr}.3"
	local client2_vlan_ip6="2021:db22:${ipaddr}::3"
	local ip4_mask_len=24
	local ip6_mask_len=64
	local vid=5
	ip link set $nic_test up

	if i_am_server; then
		ip link set $nic_test up
		sleep 1
		ip addr flush $nic_test
		sleep 1
		ip link add link $nic_test name $nic_test.$vid type vlan id $vid
		sleep 1
		ip link set $nic_test.$vid up
		sleep 1
		ip addr add ${server_vlan_ip4}/${ip4_mask_len} dev $nic_test.$vid
		sleep 1
		ip addr add ${server_vlan_ip6}/${ip6_mask_len} dev $nic_test.$vid
		sleep 1
		ip addr show $nic_test.$vid

		sync_set client ${test_name}_phase1_start
		sync_wait client ${test_name}_phase1_end

		ip link del $nic_test.$vid
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		sleep 1
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		ip addr show $nic_test

		sync_set client ${test_name}_phase2_start
		sync_wait client ${test_name}_phase2_end

		ip addr flush $nic_test
	else
		sync_wait server ${test_name}_phase1_start
		modprobe vfio-pci
		if ! sriov_create_vfs $nic_test 0 2;then
			let result++
			rlFail "${test_name} failed: can't create vfs."

		fi

		local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
		local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"

		local vf1_bus_info=$(sriov_get_vf_bus_info $nic_test 0 1)
		local vf1_domain=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $1}')
		local vf1_bus=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $2}')
		local vf1_slot=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $3}')
		local vf1_function=$(echo $vf1_bus_info | awk -F '[:|.]' '{print $4}')

		local vf2_bus_info=$(sriov_get_vf_bus_info $nic_test 0 2)
		local vf2_domain=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $1}')
		local vf2_bus=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $2}')
		local vf2_slot=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $3}')
		local vf2_function=$(echo $vf2_bus_info | awk -F '[:|.]' '{print $4}')

		cat <<-EOF > /usr/share/libvirt/networks/forward_hostdev.xml
			<network>
				<name>forward_hostdev</name>
				<forward mode='hostdev' managed='yes'>
						<driver name='vfio'/>
						<address type='pci' domain='0x$vf1_domain' bus='0x$vf1_bus' slot='0x$vf1_slot' function='0x$vf1_function'/>
						<address type='pci' domain='0x$vf2_domain' bus='0x$vf2_bus' slot='0x$vf2_slot' function='0x$vf2_function'/>
				</forward>
			</network>
		EOF
		cat <<-EOF > vf1.xml
			<interface type='network'>
					<source network='forward_hostdev'/>
					<target dev='vf1'/>
					<mac address='$mac1'/>
					<vlan>
						<tag id='$vid'/>
					</vlan>
			</interface>
		EOF
		cat <<-EOF > vf2.xml
			<interface type='network'>
					<source network='forward_hostdev'/>
					<target dev='vf2'/>
					<mac address='$mac2'/>
					<vlan>
						<tag id='$vid'/>
					</vlan>
			</interface>
		EOF
		virsh net-define /usr/share/libvirt/networks/forward_hostdev.xml
		virsh net-start forward_hostdev
		sleep 5
		if ! virsh attach-device $vm1 vf1.xml || \
			! virsh attach-device $vm2 vf2.xml;then
			let result++
			rlFail "${test_name} failed: can't attach vf to vm."
		fi

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{sleep 1}
			{ip addr flush \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client1_vlan_ip4}/${ip4_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client1_vlan_ip6}/${ip6_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		[ $? -ne 0 ] && rlFail "configure guest ip failed"

		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{sleep 1}
			{ip addr flush \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client2_vlan_ip4}/${ip4_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip addr add ${client2_vlan_ip6}/${ip6_mask_len} dev \$NIC_TEST}
			{sleep 1}
			{ip addr show \$NIC_TEST}
		)
		vmsh cmd_set $vm2 "${cmd[*]}"
		[ $? -ne 0 ] && rlFail "configure guest ip failed"
		#do_vm_netperf $vm2 $server_ip4 $server_ip6 $result_file
		#do_vm_netperf $vm1 $server_ip4 $server_ip6 $result_file
		#do_vm_netperf $vm1 ${client2_ip4} ${client2_ip6} $result_file
		#do_vm_netperf $vm2 $server_vlan_ip4 $server_vlan_ip6 $result_file
		#do_vm_netperf $vm1 $server_vlan_ip4 $server_vlan_ip6 $result_file
		#do_vm_netperf $vm1 ${client2_vlan_ip4} ${client2_vlan_ip6} $result_file

		#ping in the same should success
		vmsh run_cmd $vm1 "timeout 40s bash -c \"until ping -c3 ${server_vlan_ip4}; do sleep 5; done\""
		result=$?
		vmsh run_cmd $vm1 "timeout 40s bash -c \"until ping6 -c3 ${server_vlan_ip6}; do sleep 5; done\""
		let result+=$?

		vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping -c3 ${server_vlan_ip4}; do sleep 5; done\""
		let result+=$?
		vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping6 -c3 ${server_vlan_ip6}; do sleep 5; done\""
		let result+=$?

		#vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping -c3 ${client1_vlan_ip4}; do sleep 5; done\""
		#let result+=$?
		#vmsh run_cmd $vm2 "timeout 40s bash -c \"until ping6 -c3 ${client1_vlan_ip6}; do sleep 5; done\""
		#let result+=$?

		sync_set server ${test_name}_phase1_end
		sync_wait server ${test_name}_phase2_start

		#ping in different vlan should fail
		vmsh run_cmd $vm1 "timeout 10s bash -c \"until ping -c3 ${server_ip4}; do sleep 5; done\""
		(($?)) || { rlFail "ping in different vlan success"; let result++; }
		vmsh run_cmd $vm1 "timeout 10s bash -c \"until ping6 -c3 ${server_ip6}; do sleep 5; done\""
		(($?)) || { rlFail "ping6 in different vlan success"; let result++; }

		if [[ $ENABLE_RT_KERNEL != "yes" ]]; then
			virsh detach-device g1 vf1.xml || { rlFail "detach vf1 failed"; let result++; }
			sleep 3
			virsh detach-device g2 vf2.xml || { rlFail "detach vf2 failed"; let result++; }
			sleep 3
		else
			virsh detach-device g1 vf1.xml --config
			virsh detach-device g2 vf2.xml --config
			virsh shutdown g1
			virsh shutdown g2
			sleep 10
			virsh start g1
			virsh start g2
			sleep 10
			local vm1_status=$(virsh list --all | grep g1 |  awk '{print $3,$4}')
			local vm2_status=$(virsh list --all | grep g2 |  awk '{print $3,$4}')
			rlLog "current g1 and g2 guest status is ${vm1_status}, ${vm2_status}"
		fi
		virsh net-destroy forward_hostdev
		virsh net-undefine forward_hostdev
		sriov_remove_vfs $nic_test 0 || { rlFail "remove vf failed"; let result++; }

		sync_set server ${test_name}_phase2_end
	fi

	return $result
}

sriov_test_vmvf_max_tx_rate()
{
	log_header "VMVF max_tx_rate" $result_file
	local result=0

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		sync_set client test_vmvf_max_tx_rate_start
		sync_wait client test_vmvf_max_tx_rate_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_vmvf_max_tx_rate_start

	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"

	sriov_create_vfs $nic_test 0 2

		#ensure netserver is running
		local cmd=(
			{iptables -F}
			{ip6tables -F}
			{systemctl stop firewalld}
			{pkill netserver\; sleep 2\; netserver}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		vmsh cmd_set $vm2 "${cmd[*]}"

	# setup vmvf1
	if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac1; then
		result=1
	fi

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
		{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
		{ip link show \$NIC_TEST}
		{ip addr show \$NIC_TEST}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"

	# setup vmvf2
	if ! sriov_attach_vf_to_vm $nic_test 0 2 $vm2 $mac2; then
		result=1
	fi

	local cmd=(
		{export NIC_TEST=\$\(ip link show \| grep $mac2 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
		{ip link set \$NIC_TEST up}
		{ip addr flush \$NIC_TEST}
		{ip addr add 172.30.${ipaddr}.21/24 dev \$NIC_TEST}
		{ip addr add 2021:db8:${ipaddr}::21/64 dev \$NIC_TEST}
		{ip link show \$NIC_TEST}
		{ip addr show \$NIC_TEST}
	)
	vmsh cmd_set $vm2 "${cmd[*]}"

	local vm1_max_tx_rate=100
	local vm2_max_tx_rate=200
	ip link set $nic_test vf 0 max_tx_rate $vm1_max_tx_rate || { rlFail "set vf 0 max_tx_rate failed";result=1; }
	ip link set $nic_test vf 1 max_tx_rate $vm2_max_tx_rate || { rlFail "set vf 1 max_tx_rate failed";result=1; }

	# test
	local vm1_ipv4_thpt=$(vm_netperf_ipv4 $vm1 172.30.${ipaddr}.1)
	local vm2_ipv4_thpt=$(vm_netperf_ipv4 $vm2 172.30.${ipaddr}.1)
	local vm1_ipv6_thpt=$(vm_netperf_ipv6 $vm1 2021:db8:${ipaddr}::1)
	local vm2_ipv6_thpt=$(vm_netperf_ipv6 $vm2 2021:db8:${ipaddr}::1)
	rlLog "$vm1_ipv4_thpt $vm1_ipv6_thpt $vm2_ipv4_thpt $vm2_ipv6_thpt"

		if (($(bc <<< "$vm1_ipv4_thpt>$(bc <<< \"$vm1_max_tx_rate*1.1\")"))); then
			((result+=1))
			rlFail "vm1_ipv4_thpt($vm1_ipv4_thpt) exceed max_rate"
		fi
		if (($(bc <<< "$vm1_ipv6_thpt>$(bc <<< \"$vm1_max_tx_rate*1.1\")"))); then
			((result+=1))
			rlFail "vm1_ipv6_thpt($vm1_ipv6_thpt) exceed max_rate"
		fi
		if (($(bc <<< "$vm2_ipv4_thpt>$(bc <<< \"$vm2_max_tx_rate*1.1\")"))); then
			((result+=1))
			rlFail "vm2_ipv4_thpt($vm2_ipv4_thpt) exceed max_rate"
		fi
		if (($(bc <<< "$vm2_ipv6_thpt>$(bc <<< \"$vm2_max_tx_rate*1.1\")"))); then
			((result+=1))
			rlFail "vm2_ipv6_thpt($vm2_ipv6_thpt) exceed max_rate"
		fi

	# clearnup
	sriov_detach_vf_from_vm $nic_test 0 1 $vm1
	sriov_detach_vf_from_vm $nic_test 0 2 $vm2

	sriov_remove_vfs $nic_test 0

	sync_set server test_vmvf_max_tx_rate_end

	return $result
}

sriov_test_vmpf_remote()
{
	log_header "VMPF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmpf_remote_start
		sync_wait client test_vmpf_remote_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmpf_remote_start

		vmsh run_cmd $vm1 "rm -f /tmp/nic_list_without_pf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_without_pf; done"

		local pf_bus_info=$(ethtool -i $nic_test | grep 'bus-info'| sed 's/bus-info: //')
		if ! sriov_attach_pf_to_vm $nic_test $vm1; then
			result=1
			rlFail "attach pf to vm failed"
		else
			vmsh run_cmd $vm1 "rm -f /tmp/nic_list_with_pf;for if in \$(ip link|grep \"<*>\"|awk -F: '{print \$2}'); do echo \$if >> /tmp/nic_list_with_pf; done"
			vmsh run_cmd $vm1 "diff /tmp/nic_list_without_pf /tmp/nic_list_with_pf|grep \">\"|awk '{print \$2}' | tee /tmp/pf"
			local cmd=(
				{export NIC_TEST=\$\(sed -n 1p /tmp/pf\)}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
				{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			result=$?

			sriov_detach_pf_from_vm $pf_bus_info $vm1
		fi

		sync_set server test_vmpf_remote_end
	fi

	return $result
}

sriov_test_create_remove_vfs_memoryleak()
{
		log_header "create_remove_vfs_memoryleak" $result_file

		local result=0

		ip link set $nic_test up

		if i_am_server; then
			sync_set client test_create_remove_vfs_memoryleak_start
			sync_wait client test_create_remove_vfs_memoryleak_end
		else
			sync_wait server test_create_remove_vfs_memoryleak_start

			local total_vfs=$(sriov_get_max_vf_from_pf ${nic_test} 0)
			local MON_FILE=./memory_monitor_$(uname -n)

			local available_mem_before=$(free|grep Mem:|awk '{print $NF}')
			date "+%Y-%m-%d %H:%M:%S" > $MON_FILE
			echo $available_mem_before >> $MON_FILE
			for i in `seq 0 100`;do
				rlLog "test$i"
					echo $total_vfs > /sys/bus/pci/devices/$pf_bus_info/sriov_numvfs
					sleep 1
					echo 0 > /sys/bus/pci/devices/$pf_bus_info/sriov_numvfs
					sleep 1
					if (( $i % 10 == 0 ));then
						cat /proc/slabinfo >> $MON_FILE
					fi
			done
			sleep 5
			local available_mem_after=$(free|grep Mem:|awk '{print $NF}')
			echo $available_mem_after >> $MON_FILE
			date "+%Y-%m-%d %H:%M:%S" >> $MON_FILE
			local mem_grow=$(bc <<< $available_mem_before-$available_mem_after)
			echo "mem_grow is $mem_grow"
			#if [ $mem_grow -gt 100000 ];then
			#	result=1
			#fi
			sync_set server test_create_remove_vfs_memoryleak_end
		fi

		return $result
}

sriov_test_vmvf_testpmd_macswap()
{
		log_header "sriov_test_vmvf_testpmd_macswap" $result_file
	local test_name="sriov_test_vmvf_testpmd_macswap"
		local result=0
	#pktgen dst mac
	local vf_mac="02:01:01:01:01:01"
	#pktgen src mac
	local src_mac="22:11:11:11:11:11"
	ip link set $nic_test up

	if i_am_server; then
		sync_wait client ${test_name}_start
		modprobe -v pktgen
		echo "rem_device_all" > /proc/net/pktgen/kpktgend_0
		echo "add_device $nic_test" > /proc/net/pktgen/kpktgend_0
		echo "src_min 1.1.1.1" > /proc/net/pktgen/$nic_test
		echo "src_max 1.1.1.1" > /proc/net/pktgen/$nic_test
		echo "dst 1.1.1.2" > /proc/net/pktgen/$nic_test
		echo "count 100" > /proc/net/pktgen/$nic_test
		echo "pkt_size 1500" > /proc/net/pktgen/$nic_test
		echo "src_mac $src_mac" > /proc/net/pktgen/$nic_test
		echo "dst_mac $vf_mac" > /proc/net/pktgen/$nic_test
		echo "delay 10000000" > /proc/net/pktgen/$nic_test
		sync_wait client ${test_name}_start_sendpkg
		tcpdump -i $nic_test ether src $vf_mac and ether dst $src_mac -w 1.cap &
		echo "start" > /proc/net/pktgen/pgctrl
		sleep 5
		pkill tcpdump;sleep 2;
		#if received pkg sent from vf, add ip on nic, so client will ping success, and client will set test result according to this
		if tcpdump -r 1.cap -ev -nn|grep $vf_mac;then
			ip addr add 192.130.1.1/24 dev $nic_test
		fi
		sync_set client ${test_name}_end_sendpkg
			sync_wait client ${test_name}_end
		ip addr flush $nic_test
		modprobe -r pktgen
	else
		sriov_config_dpdk
		sync_set server ${test_name}_start
		if [ "$NIC_DRIVER" != "ixgbe" -a "$NIC_DRIVER" != "i40e" -a "$NIC_DRIVER" != "mlx5_core" -a "$NIC_DRIVER" != "mlx4_en" ];then
			sync_set server ${test_name}_start_sendpkg
			sync_wait server ${test_name}_end_sendpkg
			sync_set server ${test_name}_end
			return 0
		fi

		if ! virsh net-list | grep default &&
			! virsh net-start default;then
				virsh net-define /usr/share/libvirt/networks/default.xml
				virsh net-start default
				virsh net-autostart default
		fi
#	ip link show | grep virbr0 || ip link add name virbr0 type bridge
#	ip link set virbr0 up

		ip link show | grep virbr1 || ip link add name virbr1 type bridge
		ip link set virbr1 up

		#download guest image
		local vmname=vm_testpmd
		rlLog "Download guest image..."
		pushd "/var/lib/libvirt/images/" 1>/dev/null
		[ -e $(basename $IMG_GUEST) ] ||  wget -nv -N $IMG_GUEST
		chmod -R 777 $(basename $IMG_GUEST)
		cp --remove-destination $(basename $IMG_GUEST) ${vmname}.qcow2
		if [ "$SYS_ARCH" == "aarch" ];then
			[ -z "$IMG_FD" ] && IMG_FD=`echo $IMG_GUEST | sed 's/.qcow2/_VARS.fd/g'`
			[ -e $(basename $IMG_FD) ] || wget -nv -N $IMG_FD
			chmod -R 777 $(basename $IMG_FD)
			cp --remove-destination $(basename $IMG_FD) ${vmname}.fd
		fi
		popd 1>/dev/null

		#create vm
		if ! virsh list | grep "$vmname " && ! virsh start $vmname;then
			rlLog "Creating guest $vmname..."
			if [ "$SYS_ARCH" == "aarch" ];then
				pci_str=$(for i in `seq 1 15`;do echo -n "--controller type=pci,index=$i,model=pcie-root-port ";done)
				virt-install \
					--name $vmname \
					--vcpus=9 \
					--cpu mode=host-passthrough \
					--ram=$((8192/2)) \
					--memorybacking hugepages=yes,size=1,unit=G \
					--disk path=/var/lib/libvirt/images/${vmname}.qcow2,device=disk,bus=virtio,format=qcow2 \
					--network bridge=virbr0,model=virtio \
					--accelerate \
					--force \
					--graphics none \
					--os-variant=rhel-unknown \
					--noautoconsole \
					--boot loader=/usr/share/AAVMF/AAVMF_CODE.fd,loader_ro=yes,loader_type=pflash,nvram=/var/lib/libvirt/images/${vmname}.fd,loader_secure=no \
					--controller type=pci,index=0,model=pcie-root  \
					$pci_str

				else
					virt-install \
						--name $vmname \
						--vcpus=9 \
						--cpu mode=host-passthrough \
						--ram=$((8192/2)) \
						--memorybacking hugepages=yes,size=1,unit=G \
						--disk path=/var/lib/libvirt/images/${vmname}.qcow2,device=disk,bus=virtio,format=qcow2 \
						--network bridge=virbr0,model=virtio \
						--boot hd \
						--accelerate \
						--force \
						--graphics none \
						--os-variant=rhel-unknown \
						--noautoconsole
			fi
			# wait VM bootup
			sleep 90
			# update VM kernel to the same one as host
			sriov_config_vm_repo $vmname
			local k="yum install -y $RPM_KERNEL $RPM_KERNEL_CORE $RPM_KERNEL_MODULES $RPM_KERNEL_MODULES_INTERNAL"
			vmsh run_cmd $vmname "$k"
			virsh reboot $vmname
			sleep 120
			if (($rhel_version >= 8)); then
				virsh destroy $vmname
				sleep 2
				virsh start $vmname
				sleep 60
			fi

			# vm setup
			local cmd=(
				{iptables -F}
				{ip6tables -F}
				{systemctl stop firewalld}
				{setenforce 0}
				{yum install -y bzip2}
				{yum install -y wget}
				{yum -y install wget unzip tcpdump automake gcc make}
				{wget -nv -N http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/tools/netperf-20160222.tar.bz2}
				{tar xf $(basename http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/tools/netperf-20160222.tar.bz2)}
				{pushd netperf-*/}
				{./autogen.sh}
				{./configure CFLAGS=-fcommon}
				{make}
				{make install}
				{popd}
				{pkill netserver\; sleep 2\; netserver}
				# work around bz883695
				{lsmod \| grep mlx4_en \|\| modprobe mlx4_en}
				{tshark -v \&\>/dev/null \|\| yum -y install wireshark}
				)
				if (($rhel_version >= 7)); then
					vmsh run_cmd $vmname "systemctl stop NetworkManager"
				fi
				vmsh cmd_set $vmname "${cmd[*]}"

		fi

		#config dpdk
		local cmd=(
			{yum install -y pciutils}
			{yum install -y python2}
			{rpm -ivh $DPDK_URL}
			{rpm -ivh $DPDK_TOOLS_URL}
			{sed -i \'s/default_hugepagesz=[0-9]\\\+[MGmg]//g\'  /etc/default/grub}
			{sed -i \'s/hugepagesz=[0-9]\\\+[MGmg]//g\'  /etc/default/grub}
			{sed -i \'s/hugepages=[0-9]\\\+//g\'  /etc/default/grub}
			{export CMDLINE=\$\(grep GRUB_CMDLINE_LINUX /etc/default/grub \| awk -F\'\"\' \'\{print \$2\}\'\)}
			{export NEW_CMDLINE=\"\\\"\$CMDLINE default_hugepagesz=1G hugepagesz=1G hugepages=2\\\"\"}
			{echo \"\$CMDLINE and \$NEW_CMDLINE\"}
			{eval \"sed -i \'s:GRUB_CMDLINE_LINUX.*:GRUB_CMDLINE_LINUX=\$NEW_CMDLINE:g\' /etc/default/grub\"}
			{grub2-mkconfig -o /boot/grub2/grub.cfg}
			{yum install -y libibverbs}
			{echo options mlx4_core log_num_mgm_entry_size=-1  \>\> /etc/modprobe.d/mlx4.conf}
			{dracut -f -v}
			{mkdir /mnt/huge}
			{mount -t hugetlbfs nodev /mnt/huge}
			{modprobe vfio-pci}
			{ln -s /usr/bin/python2 /usr/bin/python}
		)
		vmsh cmd_set $vmname "${cmd[*]}"
		virsh reboot $vmname
		sleep 90

		#load vfio-pci module
		local cmd=(
			{mount -t hugetlbfs nodev /mnt/huge}
			{modprobe -r vfio_iommu_type1}
			{modprobe -r vfio}
			{modprobe -v vfio enable_unsafe_noiommu_mode=1}
			{modprobe -v vfio-pci}
		)
		vmsh cmd_set $vmname "${cmd[*]}"

		#create vf and attach it to vm then run test
		sriov_create_vfs $nic_test 0 1
		sriov_attach_vf_to_vm $nic_test 0 1 $vmname $vf_mac
		local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $vf_mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{echo \$\(ethtool -i \$NIC_TEST\|grep bus-info\|awk \'\{print \$2\}\'\) \> /home/nic_bus_info}
			{ip link set \$NIC_TEST down}
		)
		#mlx is different with other nic, don't need bind nic to vfio-pci
		vmsh cmd_set $vmname "${cmd[*]}"
		if [ "$NIC_DRIVER" != "mlx4_en" -a "$NIC_DRIVER" != "mlx5_core" ];then
			vmsh run_cmd $vmname "dpdk-devbind -b vfio-pci \$(cat /home/nic_bus_info)"
		fi
		VMSH_PROMPT1="testpmd>" VMSH_NORESULT=1 VMSH_NOLOGOUT=1 vmsh run_cmd $vmname "testpmd -l 0,1,2 -n 4 -w \$(cat /home/nic_bus_info) --socket-mem 1024 -- --nb-cores=2 --rxq=1 --txq=1 --rxd=2048 --txd=2048 --port-topology=chained --forward-mode=macswap --auto-start \> /home/log 2\>\&1"
		sync_set server ${test_name}_start_sendpkg
		sync_wait server ${test_name}_end_sendpkg
		ip addr add 192.130.1.2/24 dev $nic_test
		sleep 5
		if ! ping -c5 192.130.1.1;then
			rlFail "failed: server didn't receive packet sent from vf"
			result=1
		fi

		#clear
		sriov_detach_vf_from_vm $nic_test 0 1 $vmname
		sriov_remove_vfs $nic_test 0
		virsh shutdown $vmname
		ip addr flush $nic_test
		sync_set server ${test_name}_end
	fi

	return $result
}

#create vfs via "echo ${num_vfs} > /sys/class/net/$PF/device/sriov_numvfs"
sriov_test_vf_creation()
{
	log_header "VF ---- REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vf_create_start
		sync_wait client test_vf_cteate_end

		ip addr flush $nic_test
	else
		sync_wait server test_vf_create_start
		rlLog "#### create vfs via echo 2 > /sys/class/net/${nic_test}/device/sriov_numvfs ####"

		if ! sriov_create_vfs_1 $nic_test 0 2; then
			sync_set server test_vf_create_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			rlFail "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
				#workaround for ionic bz1914175
				ip link set dev $vf address 00:de:ad:$(printf "%02x" $ipaddr):01:01
				ip link set $vf down
				sleep 2
			fi
			ip link set $vf up
			sleep 5
			ip addr flush $vf
			ip addr add 172.30.${ipaddr}.1/24 dev $vf
			ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
			ip -d link show $vf
			ip -d addr show $vf

			do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
			local result=$?

			ip addr flush $vf
		fi
		sriov_remove_vfs $nic_test 0

		sync_set server test_vf_create_end
	fi

	return $result
}

sriov_test_vf_vlan_negative()
{

	#vlan negative testing, like setting vlan -1/0/4096
	#reproducer for bz1859477, run the command with the VF netdev, should just fail without a kernel panic
	local result=0
	local vid="-1 0 4096"

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vf_vlan_neg_start
		sync_wait client test_vf_vlan_neg_end

	else
		sync_wait server test_vf_vlan_neg_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_vlan_neg_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			rlFail "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf %02x ${ipaddr}):01:01
				ip link set $vf down
				sleep 2
			fi

			ip link set $vf up
			sleep 5
			for i in $vid;
			do
				rlRun "ip link set dev $nic_test vf 0 vlan $i" "0-255"
				sleep 2
				ip link show dev $nic_test
			done

			rlLog "reproducer for bz1859477, run the command with the VF netdev, should just fail without a kernel panic"
			rlRun "ip link set dev $vf vf 0 vlan 3" "1-255"

		fi

		sriov_remove_vfs $nic_test 0

		sync_set server test_vf_vlan_neg_end
	fi

	return $result
}

sriov_test_vf_pf_speed_consistency()
{
	#reproducer for 1844598, vf speed and pf speed should be consistent
	local result=0
	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vf_pf_speed_start
		sync_wait client test_vf_pf_speed_end

	else
		sync_wait server test_vf_pf_speed_start

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vf_pf_speed_end
			return 1
		fi

		local vf=$(sriov_get_vf_iface $nic_test 0 1)
		if [ -z "$vf" ]; then
			rlFail "FAIL to get VF interface"
			result=1
		else
			ethtool -i $vf

			if sriov_vfmac_is_zero $nic_test 0 1; then
				ip link set $nic_test vf 0 mac 00:de:ad:$(printf %02x ${ipaddr}):01:01
				ip link set $vf down
				sleep 2
			fi

			ip link set $vf up
			sleep 5
			pf_speed=`ethtool $nic_test | grep -i 'speed' | grep -o '[0-9]\+'`
			rlLog "pf speed is $pf_speed"
			vf_speed=`ethtool $vf | grep -i 'speed' | grep -o '[0-9]\+'`
			rlLog "vf speed is $vf_speed"
			[ x"$pf_speed" != x"$vf_speed" ] && result=1

		fi

		sriov_remove_vfs $nic_test 0
		sync_set server test_vf_pf_speed_end
	fi

	return $result
}

sriov_test_vf_remote_jumbo_switchdev()
{
	log_header "VF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip link set mtu 9000 dev $nic_test
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vf_remote_jumbo_switchdev_start
		sync_wait client test_vf_remote_jumbo_switchdev_end

		ip addr flush $nic_test
		ip link set mtu 1500 dev $nic_test
	else
		#sync_wait server test_vf_remote_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family' 'Intel-Ethernet_Controller_E810C_for_QSFP' 'Intel-Ethernet_Controller_E810C_for_SFP' 'Intel-Ethernet_Controller_E810C_for_backplane' 'Intel-Ethernet_Controller_E810XXV_for_SFP)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			switchdev_setup_nfp
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
						ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi
			sync_wait server test_vf_remote_jumbo_switchdev_start

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_vf_remote_jumbo_switchdev_end
				return 1
			fi

			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			if [ -z "$vf" ]; then
				rlFail "FAILED to get VF interface"
				result=1
			else
				ethtool -i $vf

				if sriov_vfmac_is_zero $nic_test 0 1; then
					ip link set $nic_test vf 0 mac 00:de:ad:$(printf "%02x" $ipaddr):01:01
					ip link set $vf down
					sleep 2
				fi

				switchdev_setup_mlx
				#workaround for bz1877274
				nic_test=$(get_required_iface)
				ip link set $nic_test up
				ip link set mtu 9000 dev $nic_test
				sleep 2
				ip link show $nic_test

				local reps=$(switchdev_get_reps $nic_test)
				if [ -z "$reps" ]; then
					rlFail "FAILED to get representor"
					result=1
				else
					rlRun "ip link set mtu 9000 dev $vf"
					ip link set $nic_test master hostbr0
					rlLog "rep list $reps"
					for rep in $reps
					do
						ip link show $rep
						ip link set $rep up
						ip link set $rep master hostbr0
						rlRun "nmcli device set $rep managed no"
						ip link set mtu 9000 dev $rep || result=1
					done
					ip link set $vf up
					sleep 5
					ip link show
					ip addr flush $vf
					ip addr add 172.30.${ipaddr}.1/24 dev $vf
					ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
					ip -d link show $vf
					ip -d addr show $vf

					do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
					local result=$?

					ip addr flush $vf
				fi
			fi

			switchdev_cleanup_mlx
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0
			ip link set mtu 1500 dev $nic_test

			sync_set server test_vf_remote_jumbo_switchdev_end
		else
			sync_wait server test_vf_remote_jumbo_switchdev_start
			sync_set server test_vf_remote_jumbo_switchdev_end
		fi
	fi

	return $result
}

sriov_test_vmvf_remote_switchdev()
{
	log_header "VMVF <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmvf_remote_switchdev_start
		sync_wait client test_vmvf_remote_switchdev_end

		ip addr flush $nic_test
	else
		#sync_wait server test_vmvf_remote_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family' 'Intel-Ethernet_Controller_E810C_for_QSFP' 'Intel-Ethernet_Controller_E810C_for_SFP' 'Intel-Ethernet_Controller_E810C_for_backplane' 'Intel-Ethernet_Controller_E810XXV_for_SFP)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			switchdev_setup_nfp
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
						ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi
			sync_wait server test_vmvf_remote_switchdev_start

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_vmvf_remote_switchdev_end
				return 1
			fi

			switchdev_setup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)

			#check the vm state, re-start it if not running
			g1_state=$(virsh list --all | grep g1 | awk '{print $3}')
			if [ x"$g1_state" != x"running" ]
			then
				virsh start g1
				sleep 10
			fi

			local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local reps=$(switchdev_get_reps $nic_test)
			if [ -z "$reps" ]; then
				rlFail "FAILED to get representor"
				result=1
			else
				ip link set $nic_test master hostbr0
				rlLog "rep list $reps"
				for rep in $reps
				do
					ip link show $rep
					ip link set $rep up
					ip link set $rep master hostbr0
					rlRun "nmcli device set $rep managed no"
				done
				ip link set $vf up
				sleep 5
				ip link show
			fi

			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
				result=1
			else
				local cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST up}
					{ip addr flush \$NIC_TEST}
					{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
					{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
					{ip link show \$NIC_TEST}
					{ip addr show \$NIC_TEST}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
				local result=$?
			fi
			#clean up
			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			switchdev_cleanup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0

			sync_set server test_vmvf_remote_switchdev_end
		else
			sync_wait server test_vmvf_remote_switchdev_start
			sync_set server test_vmvf_remote_switchdev_end
		fi
	fi

	return $result
}

sriov_test_vmvf_remote_jumbo_switchdev()
{
	log_header "VMVF JUMBO SWITCHDEV<---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip link set mtu 9000 dev $nic_test || { result=1; rlFail "failed to set mtu 9000"; }
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vmvf_remote_jumbo_switchdev_start
		sync_wait client test_vmvf_remote_jumbo_switchdev_end

		ip addr flush $nic_test
		ip link set mtu 1500 dev $nic_test
	else
		#sync_wait server test_vmvf_remote_jumbo_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family' 'Intel-Ethernet_Controller_E810C_for_QSFP' 'Intel-Ethernet_Controller_E810C_for_SFP' 'Intel-Ethernet_Controller_E810C_for_backplane' 'Intel-Ethernet_Controller_E810XXV_for_SFP)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			switchdev_setup_nfp
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
						ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi
			sync_wait server test_vmvf_remote_jumbo_switchdev_start

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_vmvf_remote_jumbo_switchdev_end
				return 1
			fi

			switchdev_setup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)

			ip link set mtu 9000 dev $nic_test || { result=1; rlFail "failed to set mtu 9000"; }
			ip link set $nic_test up
			sleep 2
			ip link show $nic_test

			#check the vm state, re-start it if not running
			g1_state=$(virsh list --all | grep g1 | awk '{print $3}')
			if [ x"$g1_state" != x"running" ]
			then
				virsh start g1
				sleep 10
			fi

			local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local reps=$(switchdev_get_reps $nic_test)
			if [ -z "$reps" ]; then
				rlFail "FAILED to get representor"
				result=1
			else
				ip link set $nic_test master hostbr0
				rlLog "rep list $reps"
				for rep in $reps
				do
					ip link set mtu 9000 dev $rep || { result=1; rlFail "failed to set mtu 9000"; }
					ip link set $rep up
					ip link set $rep master hostbr0
					rlRun "nmcli device set $rep managed no"
					ip link show $rep
				done
				ip link set $vf up
				sleep 5
				ip link show
			fi

			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
				result=1
			else
				local cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST up}
					{ip link set mtu 9000 \$NIC_TEST}
					{sleep 5}
					{ip addr flush \$NIC_TEST}
					{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
					{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
					{ip link show \$NIC_TEST}
					{ip addr show \$NIC_TEST}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				do_vm_netperf $vm1 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
				local result=$?
			fi
			#clean up
			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			switchdev_cleanup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0
			ip link set mtu 1500 dev $nic_test

			sync_set server test_vmvf_remote_jumbo_switchdev_end
		else
			sync_wait server test_vmvf_remote_jumbo_switchdev_start
			sync_set server test_vmvf_remote_jumbo_switchdev_end
			nic_test=$(get_required_iface)
			ip link set mtu 1500 dev $nic_test
		fi
	fi

	return $result
}
sriov_test_switchdev_bz1870593()
{
	log_header "bz1870593" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_switchdev_1870593_start
		sync_wait client test_switchdev_1870593_end

		ip addr flush $nic_test
	else
		#sync_wait server test_switchdev_1870593_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family' 'Intel-Ethernet_Controller_E810C_for_QSFP' 'Intel-Ethernet_Controller_E810C_for_SFP' 'Intel-Ethernet_Controller_E810C_for_backplane' 'Intel-Ethernet_Controller_E810XXV_for_SFP)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			switchdev_setup_nfp
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
						ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi
			sync_wait server test_switchdev_1870593_start

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_switchdev_1870593_end
				return 1
			fi

			switchdev_setup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)

			#check the vm state, re-start it if not running
			g1_state=$(virsh list --all | grep g1 | awk '{print $3}')
			if [ x"$g1_state" != x"running" ]
			then
				virsh start g1
				sleep 10
			fi

			local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local reps=$(switchdev_get_reps $nic_test)
			if [ -z "$reps" ]; then
				rlFail "FAILED to get representor"
				result=1
			else
				ip link set $nic_test master hostbr0
				rlLog "rep list $reps"
				for rep in $reps
				do
					ip link show $rep
					ip link set $rep up
					ip link set $rep master hostbr0
					rlRun "nmcli device set $rep managed no"
				done
				ip link set $vf up
				sleep 5
				ip link show
			fi

			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
				result=1
			else
				local cmd=(
					{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
					{ip link set \$NIC_TEST up}
					{ip addr flush \$NIC_TEST}
					{ip addr add 172.30.${ipaddr}.11/24 dev \$NIC_TEST}
					{ip addr add 2021:db8:${ipaddr}::11/64 dev \$NIC_TEST}
					{ip link show \$NIC_TEST}
					{ip addr show \$NIC_TEST}
				)
				vmsh cmd_set $vm1 "${cmd[*]}"

				#check the packet stats before running netperf
				rlLog "rep list $reps"
				for rep in $reps
				do
					rlRun "ip -s link show $rep "
					count_link1_before=`ip -s link show $rep | awk  'NR==4' | awk '{print $2}'`
				done
				vmsh run_cmd $vm1 "timeout 40s bash -c \"until ping -c10 172.30.${ipaddr}.2; do sleep 5; done\""
				result=$?
				for rep in $reps
				do
					rlRun "ip -s link show $rep"
					count_link1_after=`ip -s link show $rep | awk  'NR==4' | awk '{print $2}'`
				done
				rlAssertGreater "packets_after lager than packets_before" $count_link1_after $count_link1_before

			fi

			#clean up
			sriov_detach_vf_from_vm $nic_test 0 1 $vm1
			switchdev_cleanup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0

			sync_set server test_switchdev_1870593_end
		else
			sync_wait server test_switchdev_1870593_start
			sync_set server test_switchdev_1870593_end
		fi
	fi

	return $result
}

sriov_test_vf_not_created_bz1875338()
{
	log_header "1875338" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_1875338_start 30000
		sync_wait client test_1875338_end 30000

		ip addr flush $nic_test
	else
		sync_wait server test_1875338_start 30000
		local vf_num=5
		for ((i=0; i<1000; i++)); do
			sleep 1
			rlLog "--- test $i ---"
			echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs
			echo $vf_num > /sys/class/net/$nic_test/device/sriov_numvfs
			rlRun "vfs_virtfn=$(ls /sys/class/net/$nic_test/device/ | grep virtfn | wc -l)"
			if [[ $vfs_virtfn != "${vf_num}" ]]; then
				rlFail "FAIL to create VF func"
				ls /sys/class/net/$nic_test/device/
				echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs
				sync_set server test_1875338_end 30000
				return 1
			fi
			rlRun "VFS=$(ip link show ${nic_test} 2>/dev/null | grep "vf" | wc -l)"
			if [[ $VFS != "${vf_num}" ]]; then
				ip link show dev $nic_test
				ls /sys/class/net/$nic_test/device/
				rlFail "FAIL to create VFs"
				echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs
				sync_set server test_1875338_end 30000
				result=1
				return 1
			fi
		done
		sriov_remove_vfs $nic_test 0
		sync_set server test_1875338_end 30000
	fi
	return $result
}

sriov_test_vf_iface_not_created()
{
	log_header "vf_iface_not_created" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vf_iface_not_created_start 30000
		sync_wait client test_vf_iface_not_created_end 30000

		ip addr flush $nic_test
	else
		sync_wait server test_vf_iface_not_created_start 30000
		#get vf interface pattern
		echo 1 > /sys/class/net/$nic_test/device/sriov_numvfs
		vf=$(sriov_get_vf_iface $nic_test 0 1)
		vf_if_pattern=${vf%*${vf:(-1)}}
		echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs
		#begin to test
		local vf_num=5
		for ((i=0; i<1000; i++)); do
			sleep 1
			rlLog "--- test $i ---"
			echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs
			echo $vf_num > /sys/class/net/$nic_test/device/sriov_numvfs
			rlRun "vfs_virtfn=$(ls /sys/class/net/$nic_test/device/ | grep virtfn | wc -l)"
			if [[ $vfs_virtfn != "${vf_num}" ]]; then
				rlFail "FAIL to create VF func"
				ls /sys/class/net/$nic_test/device/
				echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs
				sync_set server test_vf_iface_not_created_end 30000
				return 1
			fi
			rlRun "VF_IFACES=$(ip link show  2>/dev/null | grep ${vf_if_pattern}  | wc -l)"
			if [[ $VF_IFACES != "${vf_num}" ]]; then
				sleep 5
				ip link show
				ls /sys/class/net/$nic_test/device/
				rlRun "VF_IFACES=$(ip link show  2>/dev/null | grep ${vf_if_pattern}  | wc -l)"
				if [[ $VF_IFACES != "${vf_num}" ]]; then
					ls /sys/class/net/$nic_test/device/
					ip link show
					echo "sleep 5 and check the iface again"
					sleep 5
					ip link show
					rlFail "FAIL to get VF interface"
					echo 0 > /sys/class/net/$nic_test/device/sriov_numvfs
					sync_set server test_vf_iface_not_created_end 30000
					result=1
					return 1
				fi
			fi
		done
		sriov_remove_vfs $nic_test 0
		sync_set server test_vf_iface_not_created_end 30000
	fi
	return $result
}

#reproducer for bz1842896
sriov_test_vmvf_hibernation()
{
	log_header "sriov_test_vmvf_hibernation" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then

		sync_set client test_vmvf_hibernation_start
		sync_wait client test_vmvf_hibernation_end

		ip addr flush $nic_test
	else
		sync_wait server test_vmvf_hibernation_start
		local mac="00:de:ad:$(printf %02x $ipaddr):01:01"

		if ! sriov_create_vfs $nic_test 0 2; then
			sync_set server test_vmvf_hibernation_end
			return 1
		fi
# need use pre-define to test this case. here is the refer to https://bugzilla.redhat.com/show_bug.cgi?id=2024503#c16
#- the root cause is that the management of the device was not passed to the vfio-pci driver (the unbind on iavf and bind to vfio-pci was not performed on host); I compared the dmesg outputs of persistent configuration in the domain XML vs hot-plugging.
#- vfio-pci did not enable the pci device for the virtual machine;
#
#Probably the device even though setup as managed='yes' in the xml file will/might not be handled properly by libvirt because the interface was hot-plugged and in the documentation (https://libvirt.org/html/libvirt-libvirt-domain.html) is stated:
#
#"Be aware that hotplug changes might not persist across a domain going into S4 state (also known as hibernation) unless you also modify the persistent domain definition."
#
#Which means that the device should be defined in the domain XML in order to be restored properly by the libvirt.
#
#So the VF interface is still managed by the host and not by the VM because the libvirt failed to enable it for the VM.
		local vf_interface=$(sriov_get_vf_iface $nic_test 0 1)
		local vf_businfo=$(ethtool -i $vf_interface | sed -n '/bus-info: / s/bus-info: //p')
		which virt-xml || yum install -y virt-install
		virt-xml $vm1 --add-device --hostdev $vf_businfo --print-diff
		virt-xml $vm1 --add-device --hostdev $vf_businfo
		virsh shutdown $vm1
		sleep 60
		virsh start $vm1
		sleep 60
		local cmd=(
			{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
			{ip link set \$NIC_TEST up}
			{ip link show \$NIC_TEST}
			{rm -rf \/var\/crash/\*}
			{systemctl hibernate}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if virsh list --all | grep $vm1 | grep -v "running"; then
			rlRun "virsh start $vm1"
		fi
		rlRun "virsh list --all"
		# check no vmcore file on guest
		local cmd=(
			{export vmcore=\$\(ls \/var\/crash \| wc -l\)}
			{test 0 = \$vmcore}
		)
		vmsh cmd_set $vm1 "${cmd[*]}"
		if [ $? != 0 ]; then
			rlFail "vmcore file on guest, please check it!!!"
		else
			rlLog "no vmcore file on guest"
		fi
		virt-xml $vm1 --remove-device --hostdev $vf_businfo --print-diff
		virt-xml $vm1 --remove-device --hostdev $vf_businfo
		virsh shutdown $vm1
		sleep 60
		virsh start $vm1
		sleep 60
		sriov_remove_vfs $nic_test 0

		sync_set server test_vmvf_hibernation_end
	fi
	return $result
}

sriov_test_vf_mac_switchdev_bz1814350()
{
	log_header "VF MAC <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_vf_mac_remote_switchdev_start
		sync_wait client test_vf_mac_remote_switchdev_end

		ip addr flush $nic_test
	else
		sync_wait server test_vf_mac_remote_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family' 'Intel-Ethernet_Controller_E810C_for_QSFP' 'Intel-Ethernet_Controller_E810C_for_SFP' 'Intel-Ethernet_Controller_E810C_for_backplane' 'Intel-Ethernet_Controller_E810XXV_for_SFP)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			switchdev_setup_ice
			ip link add name hostbr0 type bridge
						ip link set hostbr0 up
			if [[ "$NIC_DRIVER" == "ice" ]];then
				ip link set $nic_test master hostbr0
			fi

			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_vf_mac_remote_switchdev_end
				return 1
			fi

			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local mac=00:de:ad:$(printf "%02x" $ipaddr):01:01
			if [ -z "$vf" ]; then
				rlFail "FAILED to get VF interface"
				result=1
			else
				ethtool -i $vf
				rlLog "setting the vf mac via ip link set $nic_test vf 0 mac $mac"
				ip link set $nic_test vf 0 mac $mac
				rlLog "checking the vf mac"
				local mac_g="$(ip link show $nic_test | grep "vf 0" | awk '{ print $4 }')"
				if [ "$mac_g" != "$mac" ]; then
					rlFail "FAILED to change vf mac"
					result=1
				else
					rlLog "change the sriov mode to switchdev"
					switchdev_setup_mlx
					#workaround for bz1877274
					nic_test=$(get_required_iface)
					ip link set $nic_test up
					sleep 2
					ip link show $nic_test

					local reps=$(switchdev_get_reps $nic_test)
					if [ -z "$reps" ]; then
						rlFail "FAILED to get representor"
						result=1
					else
						rlLog "checking the vf mac with switchdev mode"
						local mac_g1="$(ip link show $nic_test | grep "vf 0" | awk '{ print $4 }')"
						if [ "$mac_g1" != "$mac" ]; then
							rlFail "FAILED: the vf mac reset after moving to switchdev mode"
							result=1
						else
							rlLog "PASS: the vf mac does not reset after moving to switchdev mode"
							ip link set $nic_test master hostbr0
							rlLog "rep list $reps"
							for rep in $reps
							do
								ip link show $rep
								ip link set $rep up
								ip link set $rep master hostbr0
								rlRun "nmcli device set $rep managed no"
							done
							ip link set $vf up
							sleep 5
							ip link show
							ip addr flush $vf
							ip addr add 172.30.${ipaddr}.1/24 dev $vf
							ip addr add 2021:db8:${ipaddr}::1/64 dev $vf
							ip -d link show $vf
							ip -d addr show $vf

							do_host_netperf 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2 $result_file
							local result=$?

							ip addr flush $vf
						fi
					fi
				fi
			fi

			#clean up
			switchdev_cleanup_mlx
			#workaround for bz1877274
			nic_test=$(get_required_iface)
			sriov_remove_vfs $nic_test 0
			switchdev_cleanup_ice
			ip link del hostbr0

			sync_set server test_vf_mac_remote_switchdev_end
		else
			sync_set server test_vf_mac_remote_switchdev_end
		fi
	fi

	return $result
}

sriov_test_pf_steering_switchdev_bz1856660()
{
	log_header "PF STEERING <---> REMOTE" $result_file

	local result=0

	ip link set $nic_test up

	if i_am_server; then
		ip addr flush $nic_test
		ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

		sync_set client test_pf_str_remote_switchdev_start
		sync_wait client test_pf_str_remote_switchdev_end

		ip addr flush $nic_test
	else
		sync_wait server test_pf_str_remote_switchdev_start
		local SUPPORT_MODELS=(Mellanox-MT2892_Family' 'Mellanox-MT2894_Family' 'Mellanox-MT28800_Family' 'Mellanox-MT27800_Family)
		if [[ "$SUPPORT_MODELS" =~ $NIC_MODEL ]];then
			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_pf_str_remote_switchdev_end
				return 1
			fi

			local vf=$(sriov_get_vf_iface $nic_test 0 1)
			local mac=00:de:ad:$(printf "%02x" $ipaddr):01:01
			if [ -z "$vf" ]; then
				rlFail "FAILED to get VF interface"
				result=1
			else
				switchdev_setup_mlx
				#workaround for bz1877274
				nic_test=$(get_required_iface)

				# add steering rules
				ip link set $nic_test up
				sleep 2
				ip link show $nic_test
				ip addr flush $nic_test
				ip addr add 172.30.${ipaddr}.11/24 dev $nic_test
				ping 172.30.${ipaddr}.2 -c 3
				sleep 3
				ethtool -L $nic_test combined 8
				ethtool -X $nic_test equal 6
				ethtool -U $nic_test flow-type ip4 src-ip 172.30.${ipaddr}.2 action 7 loc 1
				ip addr show $nic_test
				ethtool -u $nic_test
				ethtool -S $nic_test | grep rx7_by
				count1_before=`ethtool -S $nic_test | grep rx7_by | awk '{print $NF}'`
				ping 172.30.${ipaddr}.2 -c 10
				ethtool -S $nic_test | grep rx7_by
				count1_after=`ethtool -S $nic_test | grep rx7_by | awk '{print $NF}'`
				rlAssertGreater "packets_after lager than packets_before" $count1_after $count1_before

				switchdev_cleanup_mlx
				#workaround for bz1877274
				nic_test=$(get_required_iface)

				count2_before=`ethtool -S $nic_test | grep rx7_by | awk '{print $2}'`
				ping 172.30.${ipaddr}.2 -c 10
				count2_after=`ethtool -S $nic_test | grep rx7_by | awk '{print $2}'`
				rlAssertEquals "packets_after should equal packets_before" $count2_after $count2_before

			fi

			sriov_remove_vfs $nic_test 0
			delete_all_rules()
			{
				local dev=$1
				local rule_sum=$(ethtool -u $dev | grep -e "Total [0-9]* rules" | awk '{print $2}')
				if [ x"$rule_sum" == x"0" ];then
					return 0
				fi
				local rule_ids=$(ethtool -u $dev | grep Filter | awk '{print $2}')
				for rule in $rule_ids;do
					ethtool -U $dev delete $rule
				done
				return 0
			}

			delete_all_rules $nic_test
			ip addr flush $nic_test
			sync_set server test_pf_str_remote_switchdev_end
		else
			sync_set server test_pf_str_remote_switchdev_end
		fi
	fi

	return $result
}
#2 vfs on the same pf
sriov_test_cntvf_cntvf()
{
	log_header "CNTVF <---> CNTVF" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		sync_set client test_cntvf_cntvf_start
		sync_wait client test_cntvf_cntvf_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_cntvf_cntvf_start

	ip link set $nic_test up
	sriov_create_vfs $nic_test 0 2
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"
	local vf1=$(sriov_get_vf_iface $nic_test 0 1)
	local vf2=$(sriov_get_vf_iface $nic_test 0 2)

	if sriov_vfmac_is_zero $nic_test 0 1; then
		ip link set $nic_test vf 0 mac $mac1
		ip link set $vf1 down
		sleep 2
	fi
	if sriov_vfmac_is_zero $nic_test 0 2; then
		ip link set $nic_test vf 1 mac $mac2
		ip link set $vf2 down
		sleep 2
	fi

	ip link set $vf1 up
	ip link set $vf2 up
	sleep 5

	sriov_setup_container

	if ! sriov_attach_vf_to_cnt $nic_test 0 1 $container1; then
		rlFail 'failed to attach vf to container1'
		# clearnup
		sriov_clean_pod_container
		sync_set server test_cntvf_cntvf_end
		return 1
	fi

	if ! sriov_attach_vf_to_cnt $nic_test 0 2 $container2; then
		rlFail 'failed to attach vf to container2'
		# clearnup
		sriov_clean_pod_container
		sync_set server test_cntvf_cntvf_end
		return 1
	fi

	# setup cntvf1
	podman exec $container1 ip addr flush $vf1
	podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1
	podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1
	podman exec $container1 ip link show $vf1
	podman exec $container1 ip addr show $vf1

	# setup cntvf2
	podman exec $container2 ip addr flush $vf2
	podman exec $container2 ip addr add 172.30.${ipaddr}.21/24 dev $vf2
	podman exec $container2 ip addr add 2021:db8:${ipaddr}::21/64 dev $vf2
	podman exec $container2 ip link show $vf2
	podman exec $container2 ip addr show $vf2

	#ensure iperf3 server is running
	podman exec $container2 iperf3 -s -p 50001 -V --logfile ./serverlog &
	sleep 5

	# test
	local result=0
	if ! podman exec $container1 iperf3 -c 172.30.${ipaddr}.21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 172.30.${ipaddr}.21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $nic_test 0

	sync_set server test_cntvf_cntvf_end

	return $result
}

sriov_test_cntvf_cntvf_vlan()
{
	log_header "CNTVF_VLAN <---> CNTVF_VLAN" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		sync_set client test_cntvf_cntvf_vlan_start
		sync_wait client test_cntvf_cntvf_vlan_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_cntvf_cntvf_vlan_start

	ip link set $nic_test up
	sriov_create_vfs $nic_test 0 2
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"
	local vf1=$(sriov_get_vf_iface $nic_test 0 1)
	local vf2=$(sriov_get_vf_iface $nic_test 0 2)
	local vid=3

	if sriov_vfmac_is_zero $nic_test 0 1; then
		ip link set $nic_test vf 0 mac $mac1
		ip link set $vf1 down
		sleep 2
	fi
	if sriov_vfmac_is_zero $nic_test 0 2; then
		ip link set $nic_test vf 1 mac $mac2
		ip link set $vf2 down
		sleep 2
	fi

	ip link set $vf1 up
	ip link set $vf2 up
	sleep 5

	sriov_setup_container

	if ! sriov_attach_vf_to_cnt $nic_test 0 1 $container1; then
		sriov_clean_pod_container
		sync_set server test_cntvf_cntvf_vlan_end
		return 1
	fi

	if ! sriov_attach_vf_to_cnt $nic_test 0 2 $container2; then
		sriov_clean_pod_container
		sync_set server test_cntvf_cntvf_vlan_end
		return 1
	fi

	# setup cntvf1
	podman exec $container1 ip addr flush $vf1
	podman exec $container1 ip link add link $vf1 name $vf1.$vid type vlan id $vid
	podman exec $container1 ip link set $vf1.$vid up
	podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1.$vid
	podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1.$vid
	podman exec $container1 ip link show $vf1.$vid
	podman exec $container1 ip addr show $vf1.$vid

	# setup cntvf2
	podman exec $container2 ip addr flush $vf2
	podman exec $container2 ip link add link $vf2 name $vf2.$vid type vlan id $vid
	podman exec $container2 ip link set $vf2.$vid up
	podman exec $container2 ip addr add 172.30.${ipaddr}.21/24 dev $vf2.$vid
	podman exec $container2 ip addr add 2021:db8:${ipaddr}::21/64 dev $vf2.$vid
	podman exec $container2 ip link show $vf2.$vid
	podman exec $container2 ip addr show $vf2.$vid

	#ensure iperf3 server is running
	podman exec $container2 iperf3 -s -p 50001 -V --logfile ./serverlog &
	sleep 5

	# test
	local result=0
	if ! podman exec $container1 iperf3 -c 172.30.${ipaddr}.21 -p 50001 ; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 172.30.${ipaddr}.21 -p 50001 ; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $nic_test 0

	sync_set server test_cntvf_cntvf_vlan_end

	return $result
}

sriov_test_cntvf_cntvf_jumbo()
{
	log_header "CNTVF_JUMBO <---> CNTVF_JUMBO" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		sync_set client test_cntvf_cntvf_jumbo_start
		sync_wait client test_cntvf_cntvf_jumbo_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_cntvf_cntvf_jumbo_start

	sriov_create_vfs $nic_test 0 2
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"
	local vf1=$(sriov_get_vf_iface $nic_test 0 1)
	local vf2=$(sriov_get_vf_iface $nic_test 0 2)
	local result=0

	ip link set $nic_test up

	if sriov_vfmac_is_zero $nic_test 0 1; then
		ip link set $nic_test vf 0 mac $mac1
		ip link set $vf1 down
		sleep 2
	fi
	if sriov_vfmac_is_zero $nic_test 0 2; then
		ip link set $nic_test vf 1 mac $mac2
		ip link set $vf2 down
		sleep 2
	fi

	ip link set mtu 9000 dev $nic_test || { result=1; rlFail "failed to set mtu 9000 for PF"; }
	sleep 10

	sriov_setup_container

	ip link set $vf1 up
	ip link set $vf2 up
	sleep 10
	rlLog "check the vfs link state"
	ip link show dev $vf1
	ip link show dev $vf2

	if ! sriov_attach_vf_to_cnt $nic_test 0 1 $container1; then
		sriov_clean_pod_container
		sync_set server test_cntvf_cntvf_jumbo_end
		return 1
	fi

	if ! sriov_attach_vf_to_cnt $nic_test 0 2 $container2; then
		sriov_clean_pod_container
		sync_set server test_cntvf_cntvf_jumbo_end
		return 1
	fi

	# setup cntvf1
	podman exec $container1 ip link set dev $vf1 mtu 9000 || { let result+=1; rlFail "failed to set mtu 9000 for VF1"; }
	sleep 10
	podman exec $container1 ip addr flush $vf1
	podman exec $container1 ip link set $vf1 up
	podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1
	podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1
	podman exec $container1 ip link show $vf1
	podman exec $container1 ip addr show $vf1

	# setup cntvf2
	podman exec $container2 ip link set dev $vf2 mtu 9000 || { let result+=1; rlFail "failed to set mtu 9000 for VF2"; }
	sleep 10
	podman exec $container2 ip addr flush $vf2
	podman exec $container2 ip link set $vf2 up
	podman exec $container2 ip addr add 172.30.${ipaddr}.21/24 dev $vf2
	podman exec $container2 ip addr add 2021:db8:${ipaddr}::21/64 dev $vf2
	podman exec $container2 ip link show $vf2
	podman exec $container2 ip addr show $vf2

	#ensure iperf3 server is running
	podman exec $container2 iperf3 -s -p 50001 -V --logfile ./serverlog &
	sleep 5

	# test
	if ! podman exec $container1 iperf3 -c 172.30.${ipaddr}.21 -p 50001 ; then
		let result+=1
	fi
	if ! podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::21 -p 50001; then
		let result+=1
	fi
	if ! podman exec $container1 iperf3 -u -c 172.30.${ipaddr}.21 -p 50001 ; then
		let result+=1
	fi
	if ! podman exec $container1 iperf3 -u -c 2021:db8:${ipaddr}::21 -p 50001; then
		let result+=1
	fi

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $nic_test 0
	ip link set mtu 1500 dev $nic_test

	sync_set server test_cntvf_cntvf_jumbo_end

	return $result
}

sriov_test_cntvf_reboot()
{
	log_header "CNTVF_REBOOT <---> CNTVF_REBOOT" $result_file

	if i_am_server; then
		local vid=3
		ip link set $nic_test mtu 9000
		ip link set $nic_test up
		ip link add link $nic_test name ${nic_test}.${vid} type vlan id $vid
		ip link set ${nic_test}.${vid} up
		ip addr add 172.30.${ipaddr}.1/24 dev ${nic_test}.${vid}
		ip addr add 2021:db8:${ipaddr}::1/64 dev ${nic_test}.${vid}
		rlRun "iperf3_install"
		rlRun "iperf3 -s -p 50001 -V --logfile ./serverlog &"
		sync_set client test_cntvf__reboot_start 14400
		sync_wait client test_cntvf_reboot_end 14400
		ip addr flush ${nic_test}.${vid}
		ip link del ${nic_test}.${vid}
		return 0
	fi

	sync_wait server test_cntvf_reboot_start 14400

	ip link set $nic_test mtu 9000
	ip link set $nic_test up
	local total_vfs=$(sriov_get_max_vf_from_pf ${nic_test} 0)
	if [[ ${total_vfs} -le 8 ]]; then
		sriov_create_vfs $nic_test 0 $total_vfs
	else
		sriov_create_vfs $nic_test 0 8
	fi
	local vid=3
	vf_config1()
	{
		for i in $(seq 0 1);do
			let ii=$i+1
			echo "ii $ii"
			local mac="00:de:ad:$(printf %02x $ipaddr):01:0$i"
			local vf=$(sriov_get_vf_iface $nic_test 0 $ii)
			ip link set $nic_test vf $i trust on
			ip link set $nic_test vf $i vlan $vid qos 1
			ip link set $nic_test vf $i spoofchk off
			ip link set $nic_test vf $i mac ${mac}
			ip link set ${vf} mtu 9000
			ip link set ${vf} allmulticast on
			ip link set ${vf} up
			ip link set $nic_test vf $i max_tx_rate 200
		done
		echo "#########finished vf config#####"
		ip link show
	}


	sriov_setup_container

	local vf1=$(sriov_get_vf_iface $nic_test 0 1)
	ip link set $nic_test vf 0 vlan $vid qos 1
	for r in $(seq 1 100);do
		echo "###########loop$r##############"
		for i in $(seq 1 2);do
			if ! sriov_attach_vf_to_cnt $nic_test 0 $i $container1; then
				sriov_clean_pod_container
				sync_set server test_cntvf_reboot_end
				return 1
			fi
		done
		echo "#########config ip addr and check connection via ping#######"
		podman exec $container1 ip link show dev $vf1
		podman exec $container1 ip addr flush $vf1
		podman exec $container1 ip link set $vf1 up
		podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1
		podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1
		podman exec $container1 ip addr show $vf1
		rlRun "podman exec $container1 ping 172.30.${ipaddr}.1 -c 3"
		rlRun "podman exec $container1 ping 2021:db8:${ipaddr}::1 -c 3"
		rlRun "podman exec $container1 iperf3 -c 172.30.${ipaddr}.1 -p 50001 -t 5"
		rlRun "podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::1 -p 50001 -t 5"
		podman restart $container1
		podman ps --all
	done

	vf_config1
	for r in $(seq 1 200);do
		echo "###########loop$r##############"
		for i in $(seq 1 2);do
			if ! sriov_attach_vf_to_cnt $nic_test 0 $i $container1; then
				sriov_clean_pod_container
				sync_set server test_cntvf_reboot_end 14400
				return 1
			fi
		done
		echo "#########config ip addr and check connection via ping#######"
		podman exec $container1 ip link show dev $vf1
		podman exec $container1 ip addr flush $vf1
		podman exec $container1 ip link set $vf1 up
		podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1
		podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1
		podman exec $container1 ip addr show $vf1
		rlRun "podman exec $container1 ping 172.30.${ipaddr}.1 -c 3"
		rlRun "podman exec $container1 ping 2021:db8:${ipaddr}::1 -c 3"
		rlRun "podman exec $container1 iperf3 -c 172.30.${ipaddr}.1 -p 50001 -t 5"
		rlRun "podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::1 -p 50001 -t 5"
		podman restart $container1
		podman ps --all
	done

	# clearnup
	sriov_clean_pod_container
	sriov_remove_vfs $nic_test 0
	sync_set server test_cntvf_reboot_end 14400
	return $result
}

#on the same pf
sriov_test_podcntvf_podcntvf()
{
	log_header "POD_CNTVF <---> POD_CNTVF" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		sync_set client test_podcntvf_podcntvf_start
		sync_wait client test_podcntvf_podcntvf_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_podcntvf_podcntvf_start

	ip link set mtu 1500 dev $nic_test
	ip link set $nic_test up
	sriov_create_vfs $nic_test 0 2
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):02:01"
	local vf1=$(sriov_get_vf_iface $nic_test 0 1)
	local vf2=$(sriov_get_vf_iface $nic_test 0 2)

	if sriov_vfmac_is_zero $nic_test 0 1; then
		ip link set $nic_test vf 0 mac $mac1
		ip link set $vf1 down
		sleep 2
	fi
	if sriov_vfmac_is_zero $nic_test 0 2; then
		ip link set $nic_test vf 1 mac $mac2
		ip link set $vf2 down
		sleep 2
	fi

	ip link set $vf1 up
	ip link set $vf2 up
	sleep 5

	sriov_setup_pod_container

	if ! sriov_attach_vf_to_cnt $nic_test 0 1 $container1; then
		rlLog 'failed to attach vf to container1'
		sriov_clean_pod_container
		sync_set server test_podcntvf_podcntvf_end
		return 1
	fi

	if ! sriov_attach_vf_to_cnt $nic_test 0 2 $container3; then
		rlLog 'failed to attach vf to container3'
		sriov_clean_pod_container
		sync_set server test_podcntvf_podcntvf_end
		return 1
	fi

	# setup pod1 cntvf
	podman exec $container1 ip addr flush $vf1
	podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1
	podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1
	podman exec $container1 ip link show $vf1
	podman exec $container2 ip link show $vf1
	podman exec $container1 ip addr show $vf1

	# setup pod2 cntvf
	podman exec $container3 ip addr flush $vf2
	podman exec $container3 ip addr add 172.30.${ipaddr}.21/24 dev $vf2
	podman exec $container3 ip addr add 2021:db8:${ipaddr}::21/64 dev $vf2
	podman exec $container3 ip link show $vf2
	podman exec $container4 ip link show $vf2
	podman exec $container3 ip addr show $vf2

	#ensure iperf3 server is running
	podman exec $container3 iperf3 -s -p 50001 -V --logfile ./serverlog &
	sleep 5

	# test
	local result=0
	if ! podman exec $container1 iperf3 -c 172.30.${ipaddr}.21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 172.30.${ipaddr}.21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $nic_test 0

	sync_set server test_podcntvf_podcntvf_end

	return $result
}

#on the diff pfs
sriov_test_podcntvf1_podcntvf2()
{
	log_header "POD_CNTVF1<---> POD_CNTVF2" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		sync_set client test_podcntvf1_podcntvf2_start
		sync_wait client test_podcntvf1_podcntvf2_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_podcntvf1_podcntvf2_start

	OLD_NIC_NUM=$NIC_NUM
	OLD_NIC_DRIVER=$NIC_DRIVER
	OLD_NIC_MODEL=$NIC_MODEL
	OLD_NIC_SPEED=$NIC_SPEED

	local NIC_NUM=2
	if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
		local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
	else
		local test_iface="$(get_test_nic ${NIC_NUM})"
	fi
	if [ $? -ne 0 ];then
		echo "$test_name get required_iface failed."
		sync_set server ${test_name}_end
		return 1
	fi
	iface1=$(echo $test_iface | awk '{print $1}')
	iface2=$(echo $test_iface | awk '{print $2}')
	echo "test_ifaces:$iface1,$iface2"

	local vid=3
	local mac1="00:de:a1:$(printf %02x $ipaddr):11:01"
	local mac2="00:de:a1:$(printf %02x $ipaddr):12:01"

	if ! sriov_create_vfs $iface1 0 2 ||
	   ! sriov_create_vfs $iface2 0 2; then
	   	rlLog "${test_name} failed:create vfs failed."
	   	sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi

	ip link set $iface1 up
	ip link set $iface2 up
	local vf1=$(sriov_get_vf_iface $iface1 0 1)
	local vf2=$(sriov_get_vf_iface $iface2 0 2)

	if sriov_vfmac_is_zero $iface1 0 1; then
		ip link set $iface1 vf 0 mac $mac1
		ip link set $vf1 down
		sleep 2
	fi
	if sriov_vfmac_is_zero $iface2 0 2; then
		ip link set $iface2 vf 1 mac $mac2
		ip link set $vf2 down
		sleep 2
	fi

	ip link set $vf1 up
	ip link set $vf2 up
	sleep 5

	sriov_setup_pod_container

	if ! sriov_attach_vf_to_cnt $iface1 0 1 $container1; then
		rlLog 'failed to attach vf to container1'
		sriov_clean_pod_container
		sync_set server test_podcntvf1_podcntvf2_end
		return 1
	fi

	if ! sriov_attach_vf_to_cnt $iface2 0 2 $container3; then
		rlLog 'failed to attach vf to container3'
		sriov_clean_pod_container
		sync_set server test_podcntvf1_podcntvf2_end
		return 1
	fi

	# setup pod1 cntvf
	podman exec $container1 ip addr flush $vf1
	podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1
	podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1
	podman exec $container1 ip link show $vf1
	podman exec $container2 ip link show $vf1
	podman exec $container1 ip addr show $vf1

	# setup pod2 cntvf
	podman exec $container3 ip addr flush $vf2
	podman exec $container3 ip addr add 172.30.${ipaddr}.21/24 dev $vf2
	podman exec $container3 ip addr add 2021:db8:${ipaddr}::21/64 dev $vf2
	podman exec $container3 ip link show $vf2
	podman exec $container4 ip link show $vf2
	podman exec $container3 ip addr show $vf2

	#ensure iperf3 server is running
	podman exec $container3 iperf3 -s -p 50001 -V --logfile ./serverlog &
	sleep 5

	# test
	local result=0
	if ! podman exec $container1 iperf3 -c 172.30.${ipaddr}.21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 172.30.${ipaddr}.21 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 2021:db8:${ipaddr}::21 -p 50001; then
		result=1
	fi

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $iface1 0
	sriov_remove_vfs $iface2 0

	NIC_NUM=$OLD_NIC_NUM
	NIC_DRIVER=$OLD_NIC_DRIVER
	NIC_MODEL=$OLD_NIC_MODEL
	NIC_SPEED=$OLD_NIC_SPEED

	sync_set server test_podcntvf1_podcntvf2_end

	return $result
}

sriov_test_podcntvf_remote()
{
	log_header "POD_CNTVF <---> REMOTE" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test
		rlRun "iperf3_install"
		rlRun "iperf3 -s -p 50001 -V --logfile ./serverlog &"
		sync_set client test_podcntvf_remote_start
		sync_wait client test_podcntvf_remote_end
		ip addr flush $nic_test
		return 0
	fi

	sync_wait server test_podcntvf_remote_start

	sriov_create_vfs $nic_test 0 2
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local vf1=$(sriov_get_vf_iface $nic_test 0 1)

	if sriov_vfmac_is_zero $nic_test 0 1; then
		ip link set $nic_test vf 0 mac $mac1
		ip link set $vf1 down
		sleep 2
	fi

	ip link set $vf1 up
	sleep 5

	sriov_setup_pod_container

	if ! sriov_attach_vf_to_cnt $nic_test 0 1 $container1; then
		rlLog 'failed to attach vf to container1'
		sriov_clean_pod_container
		sync_set server test_podcntvf_remote_end
		return 1
	fi

	# setup pod1 cntvf
	podman exec $container1 ip addr flush $vf1
	podman exec $container1 ip addr add 172.30.${ipaddr}.11/24 dev $vf1
	podman exec $container1 ip addr add 2021:db8:${ipaddr}::11/64 dev $vf1
	podman exec $container1 ip link show $vf1
	podman exec $container2 ip link show $vf1
	podman exec $container1 ip addr show $vf1

	# test
	local result=0
	if ! podman exec $container1 iperf3 -c 172.30.${ipaddr}.1 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::1 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 172.30.${ipaddr}.1 -p 50001; then
		result=1
	fi
	if ! podman exec $container1 iperf3 -u -c 2021:db8:${ipaddr}::1 -p 50001; then
		result=1
	fi

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $nic_test 0

	sync_set server test_podcntvf_remote_end

	return $result
}

#refer to bug https://bugzilla.redhat.com/show_bug.cgi?id=2088787
sriov_test_podcnts_vfs_remote_bz2088787()
{
	log_header "POD_CNTVF1<---> REMOTE" $result_file

	if i_am_server; then
		ip link set $nic_test up
		ip link add link ${nic_test} name ${nic_test}.5 type vlan id 5
		ip link set $nic_test.5 up
		ip addr add 172.30.${ipaddr}.1/24 dev $nic_test.5
		ip addr add 2021:db8:${ipaddr}::1/64 dev $nic_test.5
		rlRun "iperf3_install"
		rlRun "iperf3 -s -p 50001 -V --logfile ./serverlog &"
		sync_set client ${test_name}_start
		sync_wait client ${test_name}_end
		ip addr flush $nic_test.5
		return 0
	fi

	sync_wait server test_podcntvf1_podcntvf2_start

	OLD_NIC_NUM=$NIC_NUM
	OLD_NIC_DRIVER=$NIC_DRIVER
	OLD_NIC_MODEL=$NIC_MODEL
	OLD_NIC_SPEED=$NIC_SPEED

	local NIC_NUM=2
	if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
		local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[*]})"
	else
		local test_iface="$(get_test_nic ${NIC_NUM})"
	fi
	if [ $? -ne 0 ];then
		echo "$test_name get required_iface failed."
		sync_set server ${test_name}_end
		return 1
	fi
	iface1=$(echo $test_iface | awk '{print $1}')
	iface2=$(echo $test_iface | awk '{print $2}')
	echo "test_ifaces:$iface1,$iface2"

	local vid=3
	local mac1="00:de:a1:$(printf %02x $ipaddr):11:01"
	local mac2="00:de:a1:$(printf %02x $ipaddr):12:01"

	if ! sriov_create_vfs $iface1 0 4 ||
		! sriov_create_vfs $iface2 0 4; then
		rlLog "${test_name} failed:create vfs failed."
		sriov_remove_vfs $iface1 0
		sriov_remove_vfs $iface2 0
		sync_set server ${test_name}_end
		return 1
	fi
	sriov_setup_pod_container

	ip link set $iface1 up
	ip link set $iface2 up
	for i in `seq 1 4`
	do
		local pf1vf=$(sriov_get_vf_iface $iface1 0 $i)
		ip link set $pf1vf up
		sleep 2
	done
	local pf2vf1=$(sriov_get_vf_iface $iface2 0 1)
	local pf2vf2=$(sriov_get_vf_iface $iface2 0 2)
	ip link set $pf2vf1 up
	ip link set $pf2vf2 up

	ip link set ${iface2} vf 0 spoofchk off trust on
	ip link set ${iface2} vf 1 spoofchk off trust on
	ip link set ${iface2} vf 0 vlan 5
	ip link set ${iface2} vf 1 vlan 5
	ip link set ${iface1} vf 0 vlan 51
	ip link set ${iface1} vf 0 spoofchk on trust off
	ip link set ${iface1} vf 1 vlan 52
	ip link set ${iface1} vf 1 spoofchk off trust on
	ip link set ${iface1} vf 2 vlan 51
	ip link set ${iface1} vf 2 spoofchk on trust off
	ip link set ${iface1} vf 3 vlan 52
	ip link set ${iface1} vf 3 spoofchk off trust on


	if ! sriov_attach_vf_to_cnt $iface1 0 1 $container1; then
		rlLog 'failed to attach vf to container1'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface1 0 2 $container2; then
		rlLog 'failed to attach vf to container2'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface1 0 3 $container3; then
		rlLog 'failed to attach vf to container3'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface1 0 4 $container4; then
		rlLog 'failed to attach vf to container4'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi

	if ! sriov_attach_vf_to_cnt $iface2 0 1 $container1; then
		rlLog 'failed to attach vf to container1'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi
	if ! sriov_attach_vf_to_cnt $iface2 0 2 $container3; then
		rlLog 'failed to attach vf to container3'
		sriov_clean_pod_container
		sync_set server ${test_name}_end
		return 1
	fi

	# setup pod1 cntvf
	local containerID1=$(podman ps | grep $container1 | awk '{print $1}')
	local nsID1=$(podman inspect -f '{{.State.Pid}}' $containerID1)
	ip netns exec $nsID1 ip addr flush $pf2vf1
	ip netns exec $nsID1 ip addr add 172.30.${ipaddr}.11/24 dev $pf2vf1
	ip netns exec $nsID1 ip addr add 2021:db8:${ipaddr}::11/64 dev $pf2vf1
	podman exec $container1 ip link show $pf2vf1
	podman exec $container1 ip addr show $pf2vf1

	# setup pod2 cntvf
	local containerID3=$(podman ps | grep $container3 | awk '{print $1}')
	local nsID3=$(podman inspect -f '{{.State.Pid}}' $containerID3)
	ip netns exec $nsID3 ip addr flush $pf2vf2
	ip netns exec $nsID3 ip addr add 172.30.${ipaddr}.21/24 dev $pf2vf2
	ip netns exec $nsID3 ip addr add 2021:db8:${ipaddr}::21/64 dev $pf2vf2
	podman exec $container4 ip link show $pf2vf2
	podman exec $container3 ip addr show $pf2vf2
	# test
	local result=0
	rlRun "podman exec $container1 ping 172.30.${ipaddr}.1 -c 5"
	rlRun "podman exec $container1 ping6 2021:db8:${ipaddr}::1 -c 5"
	rlRun "podman exec $container3 ping 172.30.${ipaddr}.1 -c 5"
	rlRun "podman exec $container3 ping6 2021:db8:${ipaddr}::1 -c 5"
	rlRun "podman exec $container1 iperf3 -c 172.30.${ipaddr}.1 -p 50001"
		rlRun "podman exec $container1 iperf3 -c 2021:db8:${ipaddr}::1 -p 50001"

	# clearnup
	sriov_clean_pod_container

	sriov_remove_vfs $iface1 0
	sriov_remove_vfs $iface2 0

	NIC_NUM=$OLD_NIC_NUM
	NIC_DRIVER=$OLD_NIC_DRIVER
	NIC_MODEL=$OLD_NIC_MODEL
	NIC_SPEED=$OLD_NIC_SPEED

	sync_set server ${test_name}_end

	return $result
}

sriov_test_vmvf_connectivity_remain()
{
	log_header "VF CON REMAIN <---> REMOTE" $result_file
	local result=0
	local ORIG_OS="el7"
	local TARGET_OS="el8"
	local mac1="00:de:ad:$(printf %02x $ipaddr):01:01"
	local mac2="00:de:ad:$(printf %02x $ipaddr):01:02"
	rlLog "mac1 $mac1 mac2 $mac2"
	iptables -F
	ip6tables -F
	systemctl stop firewalld
	ip link set $nic_test up
	ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
	ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test

	netperf_install

	pkill netserver && sleep 2 && netserver
	rlRun "netserver -d"

		if uname -r | grep ${TARGET_OS}; then
			sleep 60
			virsh list --all
			rlRun "nmcli connection show"
			rlRun "ip addr show "
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{nmcli con show}
				{ip addr show \$NIC_TEST}
				{ip link show \$NIC_TEST}
			)
			vmsh cmd_set $vm3 "${cmd[*]}"
			if ! do_vm_netperf $vm3 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2  $result_file; then
				result=1
				rlFail "do_vm_netperf vm3 failed."
			fi
		else

			sriov_cleanup

			rlLog "########## Enable NetworkManager on the interface ######"
			cat /etc/sysconfig/network-scripts/ifcfg-${nic_test} | \
			sed 's/NM_CONTROLLED=no/NM_CONTROLLED=yes/g' | \
			tee  /etc/sysconfig/network-scripts/ifcfg-${nic_test}

			#install VM
			rlLog "#################install VM ############"
			yum install wget -y

			virt-install --version 2>/dev/null || yum -y install virt-install
			libvirtd -V  2>/dev/null || yum -y install libvirt
			yum install -y python3-lxml.x86_64
			test -f /etc/yum.repos.d/beaker-tasks.repo && mv /etc/yum.repos.d/beaker-tasks.repo /root/beaker-tasks.repo
			rpm -qa | grep qemu-kvm >/dev/null || yum -y install qemu-kvm
			test -f /root/beaker-tasks.repo && mv /root/beaker-tasks.repo /etc/yum.repos.d/beaker-tasks.repo

			systemctl restart libvirtd
			systemctl start virtlogd.socket
			chmod 666 /dev/kvm

			# add bridge iface
			rlLog "#########add brigde virbr1 #############"
			ip link add name virbr1 type bridge
			ip link set virbr1 up
			nmcli connection add ifname virbr1 connection.type bridge con-name virbr1
			nmcli connection up virbr1
			ip link show | grep virbr1

			pushd /var/lib/libvirt/images/
			[ -e "$IMG_GUEST" ] || wget -nv -N $IMG_GUEST
			cp --remove-destination $(basename $IMG_GUEST) $vm3.qcow2
			popd

			virsh net-define /usr/share/libvirt/networks/default.xml
			virsh net-start default
			virsh net-autostart default
#	  ip link show | grep virbr0 || ip link add name virbr0 type bridge
#	  ip link set virbr0 up

		ip link show | grep virbr1 || ip link add name virbr1 type bridge
		ip link set virbr1 up
			virt-install \
			--name $vm3 \
			--vcpus=2 \
			--ram=2048 \
			--disk path=/var/lib/libvirt/images/$vm3.qcow2,device=disk,bus=virtio,format=qcow2 \
			--network bridge=virbr0,model=virtio \
			--network bridge=virbr1,model=virtio \
			--boot hd \
			--accelerate \
			--force \
			--graphics vnc,listen=0.0.0.0 \
			--os-variant=rhel-unknown \
			--noautoconsole

			# create vf
			rlLog "#############create vf############"
			nmcli con add type ethernet con-name EthernetPF-$nic_test ifname $nic_test
			nmcli con modify EthernetPF-$nic_test sriov.total-vfs 2 sriov.autoprobe-drivers false
			nmcli con modify EthernetPF-$nic_test sriov.vfs "0 mac=$mac1 , 1 mac=$mac2"
			nmcli con up EthernetPF-$nic_test
			nmcli con show
			sriov_create_vfs $nic_test 0 2
			ip link set $nic_test vf 0 mac $mac1
			ip link set $nic_test vf 1 mac $mac2
			ip addr add 172.30.${ipaddr}.2/24 dev $nic_test
			ip addr add 2021:db8:${ipaddr}::2/64 dev $nic_test
			ip link set $nic_test up
			ip link show $nic_test
			ip addr show $nic_test

			#attach vf to vm
			rlLog "##############attach vf to vm###############"
			local if1_bus=$(sriov_get_pf_bus_info $nic_test 0)
			local vf1_bus_info=$(sriov_get_vf_bus_info $nic_test 0 1)
			virsh attach-interface $vm3 hostdev $vf1_bus_info --mac $mac1 --managed --config  --live

			# vm auto start
			virsh autostart $vm3

			#add vmvf ip addr
			local vm3_ip4="172.30.${ipaddr}.11"
			local vm3_ip6="2021:db8:${ipaddr}::11"
			local ip4_mask_len=24
			local ip6_mask_len=64


			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac1 -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{nmcli con add con-name my-con-\$NIC_TEST ifname \$NIC_TEST type ethernet ip4 $vm3_ip4/24 ip6 $vm3_ip6/64}
				{ip link set \$NIC_TEST up}
				{ip addr flush \$NIC_TEST}
				{ip addr add $vm3_ip4/$ip4_mask_len dev \$NIC_TEST}
				{ip addr add $vm3_ip6/$ip6_mask_len dev \$NIC_TEST}
				{nmcli con show}
				{ip link show \$NIC_TEST}
				{ip addr show \$NIC_TEST}
			)
			vmsh cmd_set $vm3 "${cmd[*]}"

			if ! do_vm_netperf $vm3 172.30.${ipaddr}.2 2021:db8:${ipaddr}::2  $result_file; then
				result=1
				rlFail "do_vm_netperf vm3 failed."
			fi
		fi
		return $result
}

sriov_test_delete_vm_with_kernel_args()
{
	# reproduce for bug https://bugzilla.redhat.com/show_bug.cgi?id=1835705
	rlLog "Start sriov_test_delete_vm_with_kernel_args"
	if i_am_server; then
		sync_set client test_delete_vm_with_kernel_args_start 14400
		sync_wait client test_delete_vm_with_kernel_args_end 14400
		return 0
	else
		# install python environment
		which python &>/dev/null || which python3 &>/dev/null || yum -y install python3
		which python &>/dev/null || ln -s $(which python3) /usr/bin/python
		which pip &>/dev/null || which pip3 &>/dev/null || yum install -y python3-pip
		which pip &>/dev/null || ln -s $(which pip3) /usr/bin/pip
		lsmod | grep vfio_pci || modprobe vfio_pci
		# got isolate cpu expect cpu0 and cpu0's sibiling cores, but need nosmt effect after change grub file.
		if [ "$SYS_ARCH" == "ppc64le" ];then
			local numa=$(get_info.sh nic_numa_node $nic_test)
			local isolate_cores=$(get_info.sh isolated_cores $numa)
		else
			local isolate_cores=$(get_cpu.py --bug_reproduce_1835705)
		fi
		if [ -f /tmp/reboot_num ] && [[ $(cat /tmp/reboot_num) == "1" ]]; then
			if (grep "default_hugepagesz" /proc/cmdline &>/dev/null || \
				grep "hugepagesz" /proc/cmdline &>/dev/null || \
				grep "hugepages" /proc/cmdline &>/dev/null || \
				grep "isolate_cores=${isolate_cores}" /proc/cmdline &>/dev/null)
			then
				rlLog "tunning success"
				sync_wait server test_delete_vm_with_kernel_args_start 14400
			else
				rlFail "modify grub failed"
				sync_set server test_delete_vm_with_kernel_args_end 14400
			fi
		else
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz" /proc/cmdline &>/dev/null || \
			! grep "hugepages" /proc/cmdline &>/dev/null)
			then
				setup_bootopts.sh \
				--hugepagesz=2G \
				--hugepages=12 \
				--isolated_cores="$isolate_cores" \
				--extra="intel_idle.max_cstate=0 processor.max_cstate=0 intel_pstate=disable" \
				--tuned-profiles=cpu-partitioning
				echo "1" > /tmp/reboot_num
				rhts-reboot
			elif [ "$SYS_ARCH" != "ppc64le" ] && [ ! -f /tmp/reboot_num ] && (\
			! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null || \
			! grep "nosmt=force" /proc/cmdline &>/dev/null || \
			! grep "isolate_cores=${isolate_cores}" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt nosmt=force" --update-kernel=$(grubby --default-kernel)
				isolate_cores=$(get_cpu.py --bug_reproduce_1835705)
				rlLog "isolate core are ${isolate_cores}"
				# do cpu tunning on host
				if ! uname -r | grep rt; then
					rpm -q tuned-profiles-cpu-partitioning || yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
					echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
					tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
				elif uname -r | grep rt; then
					rpm -q tuned-profiles-nfv || yum install -y tuned tuned-profiles-nfv &>/dev/null
					echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
					echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
					tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
					systemctl disable irqbalance
					systemctl stop irqbalance
				fi
				rlLog "finish cpu tuning"
				# set reboot flag to tmp file
				echo "1" > /tmp/reboot_num
				rhts-reboot
			fi
		fi

		# start test
		if [ -f /tmp/reboot_num ] && [[ $(cat /tmp/reboot_num) == "1" ]]; then
			ip link show | grep virbr1 || ip link add name virbr1 type bridge
			ip link set virbr1 up

			rlLog "Create image folder"
			[ -f /home/sriov_test_delete_vm_with_kernel_args/images ] || mkdir -p /home/sriov_test_delete_vm_with_kernel_args/images


			# ensure default network start as well
			if ! virsh net-list | grep default &&
			! virsh net-start default;then
				virsh net-define /usr/share/libvirt/networks/default.xml
				virsh net-start default
				virsh net-autostart default
			fi

			local vm_num=6
			local vm_mac_perfix="00:de:aa:05:01:"

			#install VMs
			for((i=1;i<=$vm_num;i++))
			do
				local vmname=test_bug1835705_vm$i

				if virsh list --name | grep -w "$vmname" ||
					virsh start $vmname;then
					continue
				else
					rlLog "Download guest image..."
					pushd "/home/sriov_test_delete_vm_with_kernel_args/images/" 1>/dev/null
					[ -f test_bug1835705_vm$i.qcow2 ] || wget -nv $IMG_GUEST -O test_bug1835705_vm$i.qcow2
					chmod -R 777 test_bug1835705_vm$i.qcow2

					if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
					virt-copy-in -a test_bug1835705_vm$i.qcow2 ${CASE_PATH}/../../common/tools/brewkoji_install.sh /root
					fi
					popd

					rlLog "Creating guest $vmname..."
					virt-install \
					--name $vmname \
					--vcpus=1 \
					--ram=1024 \
					--disk path=/home/sriov_test_delete_vm_with_kernel_args/images/test_bug1835705_vm$i.qcow2,device=disk,bus=virtio,format=qcow2 \
					--network bridge=virbr0,model=virtio,mac=${vm_mac_perfix}$(printf %02x $i) \
					--boot hd \
					--accelerate \
					--graphics vnc,listen=0.0.0.0 \
					--force \
					--os-variant=rhel-unknown \
					--noautoconsol
				fi
				# wait VM bootup
				sleep 60
			done

			# test 20 times create vf/ attach to vm and detach
			for ((h=1;h<=20;h++)); do
				rlLog "start $h tests"
				if ! sriov_create_vfs $nic_test 0 $vm_num; then
					rlFail "ceate VF failed"
				fi
				sleep 5
				for ((i=0;i<=$(expr $vm_num - 1);i++))
				do
					ip link set $nic_test vf $i vlan 3
					sleep 5
				done

				for ((i=1;i<=$vm_num;i++))
				do
					local vf_interface_name=$(sriov_get_vf_iface $nic_test 0 $i)
					ip addr flush ${vf_interface_name}
					sleep 1
				done

				local vm_test_vf_prefix="00:de:ad:02:01:"
				local pf_bus_info=$(ethtool -i $nic_test | grep 'bus-info' | sed 's/bus-info: //')
				local vf_bus_info=($(ls -l /sys/bus/pci/devices/${pf_bus_info}/virtfn* | awk '{print $NF}' | sed 's/..\///'))

				declare -A vf_dict
				for((i=0;i<=$(expr $vm_num - 1);i++)); do
					vf_dict[$[i]]=${vf_bus_info[i]}
				done

				for j in "${!vf_dict[@]}"
				do
					virsh attach-interface --domain test_bug1835705_vm$(expr $j + 1) --type hostdev --source ${vf_dict[$j]} --mac ${vm_test_vf_prefix}$(printf %02x $j) --managed --live || rlFail "attach device failed"
				done

				for((k=1;k<=$vm_num;k++))
				do
					virsh detach-interface --domain test_bug1835705_vm$k --type hostdev --mac ${vm_test_vf_prefix}$(printf %02x $(expr $k - 1))  || rlFail "detach device failed"
					virsh reboot test_bug1835705_vm$k
				done

				for ((k=1;k<=$vm_num;k++))
				do
					vmsh run_cmd test_bug1835705_vm$k "ip link show"
				done

				sriov_remove_vfs $nic_test
				rlLog "finish $h tests"
			done
			# clean temp guests
			for ((h=1; h<$vm_num;h++))
			do
				virsh destroy test_bug1835705_vm$h
				sleep 5
				virsh undefine test_bug1835705_vm$h
			done
			rm -rf /home/sriov_test_delete_vm_with_kernel_args/images/*

			# clear cpu isolationg and nosmt parameter after finish test
			grubby --remove-args="nosmt=force" --update-kernel=$(grubby --default-kernel)
			tuned-adm off
			echo "2" > /tmp/reboot_num
			rhts-reboot
		elif [ -f /tmp/reboot_num ] && [[ $(cat /tmp/reboot_num) == "2" ]]; then
			sync_set server test_delete_vm_with_kernel_args_end 14400
		fi
		rlRun "rm -rf /tmp/reboot_num"
	fi
}

sriov_test_reproduce_2000180()
{
	# https://bugzilla.redhat.com/show_bug.cgi?id=2000180
	# this case only reproduce bug 2000180, keep cpu0 as housekeeping any other cpu will be isolated.
	# test on rt-kernel will get panic about kernel BUG at drivers/pci/msi.c:375! on i40e driver.
	# test on stock kernel will get call trace as "NETDEV WATCHDOG: ens1f0v2 (iavf): transmit queue 1 timed out" on i40e
	# if the first time to create vf, panic will occurred on the first loop. But in this case, The VF will not be
	# created for the first time after the system is available， so panic will be trigger when run 23 times.
	rlLog "Setup sriov_test_reproduce_2000180"
	# /usr/sbin/kernel-is-rt || { echo "test kernel doesn't belong to realtime kernel, skip this case"; return 0; }
	if [ "$SYS_ARCH" == "ppc64le" ];then
		rlLogWarning "this case doesn't support to run on ppc64le, due to bug 2082433"
		return 0
	fi
	if i_am_server; then
		sync_set client sriov_test_reproduce_2000180_start ${SYNC_TIME}
		[ $? -eq 0 ] && sync_wait client sriov_test_reproduce_2000180_end ${SYNC_TIME}
		return 0
	fi

	which python &>/dev/null || which python3 &>/dev/null || yum -y install python3
	which python &>/dev/null || ln -s $(which python3) /usr/bin/python

	local isolate_cores=$(get_cpu.py --bug_reproduce_2000180)
	rlLog "isolate core are ${isolate_cores}"
	if [ ! -f /tmp/sriov_test_reproduce_2000180_phase1 ]; then
		if ! uname -r | grep rt; then
			rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
			tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
		elif uname -r | grep rt; then
			rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
			echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
			tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
			systemctl disable irqbalance
			systemctl stop irqbalance
			rlLog "finish cpu tuning"
		fi
		rlLog "client finish hugepage configuration"
		echo "1" > /tmp/sriov_test_reproduce_2000180_phase1
		rhts-reboot
	else
		rlRun "lscpu"
		rlRun "cat /proc/cmdline"
	fi
	if [ ! -f /tmp/sriov_test_reproduce_2000180_phase2 ]; then
		sync_wait server sriov_test_reproduce_2000180_start ${SYNC_TIME}
		echo 1 > /tmp/sriov_test_reproduce_2000180_phase2
		rlLog "Start test"
		rlLog "Configure journalctl"
		[[ -d /var/log/journal ]] || mkdir /var/log/journal
		systemd-tmpfiles --create --prefix /var/log/journal
		echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
		systemctl restart systemd-journald.service
		rlLog "Configure finish"
		local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
		rlLog "Test nic driver is ${DRIVER}"

		rlLog "Create 5 vfs and Check vf drive type"
		local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
		local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)

		if [[ ${MAX_VFS} -le 10 ]]; then
			local test_vfs=${MAX_VFS}
		else
			local test_vfs=6
		fi
		rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"
		rlRun "sriov_remove_vfs ${nic_test} 0"
		rlLog "try to create ${test_vfs} vfs"
		rlRun "sriov_create_vfs ${nic_test} 0 6"
		sleep 10

		local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
		local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
		local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
		if [ -z ${vf_driver_name} ]; then
			rlFail "can't find vf driver"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sync_set server sriov_test_reproduce_2000180_end ${SYNC_TIME}
			exit 1
		fi
		rlLog "check all vfs are created"
		if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
			rlFail "create the test vf of pf failed"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sync_set server sriov_test_reproduce_2000180_end ${SYNC_TIME}
			exit 1
		fi

		rlLog "check no mac adress is 00:00:00:00:00:00"
		for((i=0;i<$(expr $test_vfs); i++)); do
			local test_vf_mac=$(ip link show ${nic_test} | grep "vf $i" | awk '{print$4}')
			rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_vf_mac} "00:00:00:00:00:00"
		done

		rlLog "got all of vf name on a list"
		local vf_name_list

		for ((i=1;i<=${test_vfs};i++));do
			local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
			local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
			local vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			local vf_pci_list[$(expr $i - 1)]=${VF_PCI}
		done
		rlLog "vf_name_list equal is ${vf_name_list[*]}"
		rlLog "vf pci list equal is ${vf_pci_list[*]}"
		local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))
		rlLog "sort_vf_name_list equal is ${sort_vf_name_list[*]}"

		local vf_mac_list
		for ((i=1;i<=${test_vfs};i++));do
			vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
		done
		local vf_mac_list_length=${#vf_mac_list[@]}

		rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
		rlLog "got vf mac list: ${vf_mac_list[*]}"
		rlLog "got vf mac length: ${vf_mac_list_length}"
		rlLog "clean all vf and start test"
		rlRun "sriov_remove_vfs ${nic_test} 0"
		sleep 10
		rlLog "Beginning test"
		local MTU=9000
#		modprobe vfio_pci
		for ((xx=0; xx<=3; xx++));do
			echo $xx > /tmp/sriov_test_reproduce_2000180_xx

			for ((yy=0; yy<=10; yy++)); do
				echo $yy > /tmp/sriov_test_reproduce_2000180_yy
				# 1. set numvfs
				echo "1. set numvfs"
				echo "set ${test_vfs} vfs on ${nic_test}"
				sriov_remove_vfs ${nic_test} 0
				sriov_create_vfs ${nic_test} 0 ${test_vfs}
				# echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
				# echo ${test_vfs} > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
				sleep 5

				#2. set vf admin MAC address
				echo "2. set vf admin MAC address"
				for ((i=0; i<${vf_mac_list_length}; i++)); do
					ip link set dev ${nic_test} vf ${i} mac ${vf_mac_list[$i]}
				done

				# 3. unbind/bind vf driver
				echo "unbind/bind vf driver"
				for i in "${vf_pci_list[@]}"; do
					echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
					echo > /sys/bus/pci/devices/${vf_pci}/driver_override
					echo ${i} > /sys/bus/pci/drivers_probe
				done

				# 4. set pf mtu
				echo "4. set pf mtu to ${MTU}"
				echo $MTU > /sys/class/net/${nic_test}/mtu

				#5. bind vf driver (if not already)
				#6. unbind/bind vf driver (workaround for bz1875338)
				echo "6. unbind/bind vf driver (workaround for bz1875338)"
				for i in "${vf_pci_list[@]}"; do
					echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
					echo > /sys/bus/pci/devices/${vf_pci}/driver_override
					echo ${i} > /sys/bus/pci/drivers_probe
				done

				sleep 2
				#7. set vf mtu
				echo "7. set vf mtu to ${MTU}"
				for i in "${sort_vf_name_list[@]}"; do
					echo $MTU > /sys/class/net/${i}/mtu
				done

				#8. set pf up if not already
				echo "8. set pf up if not already"

				ip link set ${nic_test} up
				echo "Iteration: xx $xx, yy $yy"
				sleep 10
				# echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
				sriov_remove_vfs ${nic_test} 0
				echo "clean vf and reset mtu to 1500"
				ip link set mtu 1500 dev $nic_test
			done
		done
	fi

	rlLog "Check that the test ends in a normal loop"
	if [[ $(cat /tmp/sriov_test_reproduce_2000180_xx) -ne 3 ]] || [[ $(cat /tmp/sriov_test_reproduce_2000180_yy) -ne 10 ]]; then
		rlFail "The test did not end in a normal cycle. please check it!!!"
	fi

	# recover tunning configuration
	local isolate_cores=$(get_cpu.py --get_isolate_cpus_str)
	rlLog "isolate core are ${isolate_cores}"
	if [ ! -f /tmp/sriov_test_reproduce_2000180_phase3 ]; then
		if ! uname -r | grep rt; then
			rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
			tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
		elif uname -r | grep rt; then
			rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
			echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
			echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
			tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
			systemctl disable irqbalance
			systemctl stop irqbalance
		fi
		rlLog "finish cpu tuning"
		echo "1" > /tmp/sriov_test_reproduce_2000180_phase3
		rhts-reboot
	fi
	sync_set server sriov_test_reproduce_2000180_end ${SYNC_TIME}
	rlLog "finish test and clean tag file"
	rm -rf /tmp/sriov_test_reproduce_2000180_xx
	rm -rf /tmp/sriov_test_reproduce_2000180_yy
	rm -rf /tmp/sriov_test_reproduce_2000180_phase3
	rm -rf /tmp/sriov_test_reproduce_2000180_phase2
	rm -rf /tmp/sriov_test_reproduce_2000180_phase1
	rlLog "check journald boot list"
	rlRun "journalctl --list-boots"
	local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
	rlLog "got prelate record id: ${prevlast}"
	rlRun "journalctl -o short-precise -k -b ${prevlast} | grep -C 50 -i \"call trace\"" 1
	rlRun "journalctl -o short-precise -k -b | grep -C 50 -i \"call trace\"" 1
	rlLog "cleanup journald setting"
	rlRun "systemd-tmpfiles --clean --prefix /var/log/journal/"
	rlRun "systemd-tmpfiles --remove --prefix /var/log/journal/"
	rlRun "systemctl restart systemd-journald.service"
	rlLog "finish test and clean tag file"
}


sriov_test_negative_create_vfs_2000180()
{
	# VFs are fully available when the echo command finishes.
	# BUT this means that PCI devices that represents VFs are available.
	# There is a second stage "binding the PCI device to driver" that is executed async.
	# it will got panic about "general protection fault: 0000 [#1] PREEMPT_RT SMP NOPTI"

	rlLog "Setup sriov_test_reproduce_negative_create_vfs_2000180"
	if i_am_server; then
		sync_set client sriov_test_negative_create_vfs_2000180_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		which python &>/dev/null || which python3 &>/dev/null || yum -y install python3
		which python &>/dev/null || ln -s $(which python3) /usr/bin/python
		if [ "$SYS_ARCH" == "ppc64le" ];then
			local numa=$(get_info.sh nic_numa_node $nic_test)
			local isolate_cores=$(get_info.sh isolated_cores $numa)
		else
			local isolate_cores=$(get_cpu.py --get_isolate_cpus_str)
		fi
		rlLog "isolate core are ${isolate_cores}"
		if [ ! -f /tmp/sriov_test_negative_create_vfs_2000180_phase1 ]; then
			if ! uname -r | grep rt; then
				rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
				tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
			elif uname -r | grep rt; then
				rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
				echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
				tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
				systemctl disable irqbalance
				systemctl stop irqbalance
				rlLog "finish cpu tuning"
			fi
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=12" /proc/cmdline &>/dev/null)
			then
				setup_bootopts.sh \
				--hugepagesz=2G \
				--hugepages=12 \
				--isolated_cores="$isolate_cores" \
				--extra="intel_idle.max_cstate=0 processor.max_cstate=0 intel_pstate=disable" \
				--tuned-profiles=cpu-partitioning
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			# ! grep "rcupdate.rcu_normal_after_boot=0" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
			else
				rlLog "client finish hugepage configuration"
			fi
			echo "1" > /tmp/sriov_test_negative_create_vfs_2000180_phase1
			rhts-reboot
		else
			rlLog "client finish cpu and hugepage tunning"
			rlRun "lscpu"
			rlRun "cat /proc/cmdline"
		fi

		if [ ! -f /tmp/sriov_test_negative_create_vfs_2000180_phase2 ]; then
			sync_wait server sriov_test_negative_create_vfs_2000180_start ${SYNC_TIME}
			rlLog "Start test"
			rlLog "Configure journalctl"
			[[ -d /var/log/journal ]] || mkdir /var/log/journal
			systemd-tmpfiles --create --prefix /var/log/journal
			echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
			systemctl restart systemd-journald.service
			rlLog "Configure finish"
			echo 1 > /tmp/sriov_test_negative_create_vfs_2000180_phase2
			local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
			rlLog "Test nic driver is ${DRIVER}"

			local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
			local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)
			local test_vfs=${MAX_VFS}
			rlLog "Create ${test_vfs} vfs and Check vf drive type"
			rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"

			rlRun "sriov_remove_vfs ${nic_test} 0"
			rlLog "try to create ${test_vfs} vfs"
			rlRun "sriov_create_vfs ${nic_test} 0 ${test_vfs}"
			sleep 120

			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
			if [ -z ${vf_driver_name} ]; then
				rlFail "can't find vf driver"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check all vfs are created"
			if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
				rlFail "create the test vf of pf failed"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check no mac adress is 00:00:00:00:00:00"
			for((i=1;i<=$(expr $test_vfs); i++)); do
				sriov_vfmac_is_zero ${nic_test} 0 ${i}
				local test_result=$?
				rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_result} 0
			done

			rlLog "got all of vf name on a list"
			local vf_name_list

			for ((i=1;i<=${test_vfs};i++));do
				local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
				local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
				vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			done

			local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))

			local vf_mac_list
			for ((i=1;i<=${test_vfs};i++));do
				vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
			done
			local vf_mac_list_length=${#vf_mac_list[@]}
			rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
			rlLog "got vf mac list: ${vf_mac_list[*]}"
			rlLog "got vf mac length: ${vf_mac_list_length}"
			rlLog "clean all vf and start test"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sleep 120
			rlLog "Beginning test"
			local MTU=9000

			for ((xx=0; xx<=3; xx++));do
				echo $xx > /tmp/sriov_test_negative_create_vfs_2000180_xx
				#not unload the VF driver in case the PF driver is the same one.
				#rmmod ${vf_driver_name}
				for ((yy=0; yy<=10; yy++)); do
					echo $yy > /tmp/sriov_test_negative_create_vfs_2000180_yy
					# 1. set numvfs
					echo "1. set numvfs"
					echo "set ${test_vfs} vfs on ${nic_test}"
					sriov_remove_vfs ${nic_test} 0
					sriov_create_vfs ${nic_test} 0 ${test_vfs}
					#2. set vf admin MAC address
					echo "2. set vf admin MAC address"
					for ((i=0; i<${vf_mac_list_length}; i++)); do
						ip link set dev ${sort_vf_name_list[$i]} address ${vf_mac_list[$i]}
					done

					# 3. unbind/bind vf driver
					echo "unbind/bind vf driver"
					for i in "${vf_pci_list[@]}"; do
						echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override
						echo ${i} > /sys/bus/pci/drivers_probe
					done

					# 4. set pf mtu
					echo "4. set pf mtu to ${MTU}"
					echo $MTU > /sys/class/net/${nic_test}/mtu

					#5. bind vf driver (if not already)
					#6. unbind/bind vf driver (workaround for bz1875338)
					echo "6. unbind/bind vf driver (workaround for bz1875338)"
					for i in "${vf_pci_list[@]}"; do
						echo ${i} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override
						echo ${i} > /sys/bus/pci/drivers_probe
					done

					#7. set vf mtu
					echo "7. set vf mtu to ${MTU}"
					for i in "${sort_vf_name_list[@]}"; do
						echo $MTU > /sys/class/net/${i}/mtu
					done

					#8. set pf up if not already
					echo "8. set pf up if not already"

					ip link set ${nic_test} up
					echo "Iteration: xx $xx, yy $yy"
					sriov_remove_vfs ${nic_test} 0

					echo "clean vf and reset mtu to 1500"
					ip link set mtu 1500 dev $nic_test

				done
			done
		fi

		rlLog "Check that the test ends in a normal loop"
		if [[ $(cat /tmp/sriov_test_negative_create_vfs_2000180_xx) -ne 3 ]] || [[ $(cat /tmp/sriov_test_negative_create_vfs_2000180_yy) -ne 10 ]]; then
			rlFail "The test did not end in a normal cycle. please check it!!!"
		fi
		rlLog "finish test and clean tag file"
		sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_xx
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_yy
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_phase2
		rm -rf /tmp/sriov_test_negative_create_vfs_2000180_phase1
		rlLog "check journald boot list"
		rlRun "journalctl --list-boots"
		local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
		rlLog "got prelate record id: ${prevlast}"
		rlRun "journalctl -o short-precise -k -b ${prevlast} | grep -C 50 -i \"call trace\"" 1
		rlRun "journalctl -o short-precise -k -b | grep -C 50 -i \"call trace\"" 1
		rlLog "cleanup journald setting"
		rlRun "systemd-tmpfiles --clean --prefix /var/log/journal/"
		rlRun "systemd-tmpfiles --remove --prefix /var/log/journal/"
		rlRun "systemctl restart systemd-journald.service"
		rlLog "finish test and clean tag file"
#		local user=$(cat /etc/motd | grep SUBMITTER | awk -F "=" '{print $2}' | sed  's/\(.*\)@.*/\1/g')
#		local jobid=$(cat /etc/motd | grep JOBID | awk -F "=" '{print $2}' | tr -d '\n' | tr -d " ")
#		local kernel_version=$(uname -r)
#		local hostname=$(hostname)
#		rlLog "try to use jobid: ${jobid}, kernel verion: ${KERNEL_VERSION}, username: ${user}, hostname: ${hostname} to find vmcore"
#		local file_list=$(find /var/crash/${user}/${KERNEL_VERSION}/${jobid}/${hostname}/ -name vmcore*)
#		if [[ ${file_list} != "" ]]; then
#			rlFail "can find vmcore file, need to check"
#		else
#			rlLog "can't find vmcore"
#		fi
		return 0

	fi
}

sriov_test_reproduce_2021326()
{
	# should got call trace as Oops: 0000 [#1] SMP NOPTI, only support ice & i40e
	# reproduce bug 2021326,2009461,1997012

	rlLog "Setup sriov_test_reproduce_2021326"
	if i_am_server; then
		sync_set client sriov_test_reproduce_2021326_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client sriov_test_reproduce_2021326_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		if [ ! -f /tmp/sriov_test_reproduce_2021326_phase1 ]; then
			local isolate_cores=$(get_cpu.py --get_isolate_cpus_str)
			rlLog "isolate core are ${isolate_cores}"
			if ! uname -r | grep rt; then
				rpm -q tuned-profiles-cpu-partitioning || rlLog "try to install tuned-profiles-cpu-partitioning" && yum install -y tuned tuned-profiles-cpu-partitioning &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/cpu-partitioning-variables.conf
				tuned-adm profile cpu-partitioning || rlFail "enable cpu-partitioning profile failed"
			elif uname -r | grep rt; then
				rpm -q tuned-profiles-nfv || rlLog "try to install tuned-profiles-nfv" && yum install -y tuned tuned-profiles-nfv &>/dev/null
				echo "isolated_cores=${isolate_cores}" > /etc/tuned/realtime-virtual-host-variables.conf
				echo "isolate_managed_irq=Y" >> /etc/tuned/realtime-virtual-host-variables.conf
				tuned-adm profile realtime-virtual-host || rlFail "enable realtime-virtual-host failed"
				systemctl disable irqbalance
				systemctl stop irqbalance
				rlLog "finish cpu tuning"
			fi
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=12" /proc/cmdline &>/dev/null)
			then
				setup_bootopts.sh \
				--hugepagesz=2G \
				--hugepages=12 \
				--isolated_cores="$isolate_cores" \
				--extra="intel_idle.max_cstate=0 processor.max_cstate=0 intel_pstate=disable" \
				--tuned-profiles=cpu-partitioning
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			# ! grep "rcupdate.rcu_normal_after_boot=0" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
			else
				rlLog "client finish hugepage configuration"
			fi
			echo "1" > /tmp/sriov_test_reproduce_2021326_phase1
			rhts-reboot
		else
			rlLog "client finish cpu and hugepage tunning"
			rlRun "lscpu"
			rlRun "cat /proc/cmdline"
		fi
		if [ ! -f /tmp/sriov_test_reproduce_2021326 ]; then
			sync_wait server sriov_test_reproduce_2021326_start ${SYNC_TIME}
			rlLog "Start test"
			rlLog "Configure journalctl"
			[[ -d /var/log/journal ]] || mkdir /var/log/journal
			systemd-tmpfiles --create --prefix /var/log/journal
			echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
			systemctl restart systemd-journald.service
			rlLog "Configure finish"
			echo 1 > /tmp/sriov_test_reproduce_2021326
			local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
			rlLog "Test nic driver is ${DRIVER}"

			rlLog "Create 10 vfs and Check vf drive type"
			local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
			local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)
			if [[ ${MAX_VFS} -le 10 ]]; then
				local test_vfs=${MAX_VFS}
			else
				local test_vfs=10
			fi
			rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"

			rlRun "sriov_remove_vfs ${nic_test} 0"
			rlLog "try to create ${test_vfs} vfs"
			rlRun "sriov_create_vfs ${nic_test} 0 ${test_vfs}"
			sleep 10

			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
			if [ -z ${vf_driver_name} ]; then
				rlFail "can't find vf driver"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check all vfs are created"
			if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
				rlFail "create the test vf of pf failed"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_end ${SYNC_TIME}
				exit 1
			fi

			rlLog "check no mac adress is 00:00:00:00:00:00"
			for((i=0;i<$(expr $test_vfs); i++)); do
				local test_vf_mac=$(ip link show ${nic_test} | grep "vf $i" | awk '{print$4}')
				rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_vf_mac} "00:00:00:00:00:00"
			done

			rlLog "got all of vf name on a list"
			local vf_name_list

			for ((i=1;i<=${test_vfs};i++));do
				local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
				local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
				vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			done

			local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))

			local vf_mac_list
			for ((i=1;i<=${test_vfs};i++));do
				vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
			done

			local vf_mac_list_length=${#vf_mac_list[@]}
			rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
			rlLog "got vf mac list: ${vf_mac_list[*]}"
			rlLog "got vf mac length: ${vf_mac_list_length}"
			rlLog "clean all vf and start test"
			rlRun "sriov_remove_vfs ${nic_test} 0"

			rlLog "Beginning test"
			local MTU=9000

			for ((xx=0; xx<=3; xx++));do
				echo $xx > /tmp/sriov_test_reproduce_2021326_xx
				rmmod ${vf_driver_name}
				sleep 1e-06
				for ((yy=0; yy<=10; yy++)); do
					echo $yy > /tmp/sriov_test_reproduce_2021326_yy
					# 1. set numvfs
					echo "1. set numvfs"
					echo "set ${test_vfs} vfs on ${nic_test}"
					echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
					echo ${test_vfs} > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
					sleep 1e-06
					#2. set vf admin MAC address
					echo "2. set vf admin MAC address"
					for ((i=1;i<=${test_vfs};i++)); do
						local vf_mac=${vf_mac_list[$(expr $i - 1)]}
						sleep 1e-06
						ip link set dev $nic_test vf $(expr $i - 1) mac ${vf_mac}
					done

					# 3. unbind/bind vf driver
					echo "unbind/bind vf driver"
					for ((i=1;i<=${test_vfs};i++)); do
						local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
						echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
						sleep 1
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override
						sleep 1
						echo ${vf_pci} > /sys/bus/pci/drivers_probe
					done

					# 4. set pf mtu
					echo "4. set pf mtu to ${MTU}"
					echo $MTU > /sys/class/net/${nic_test}/mtu

					#5. bind vf driver (if not already)
					#6. unbind/bind vf driver (workaround for bz1875338)
					echo "6. unbind/bind vf driver (workaround for bz1875338)"
					for ((i=1;i<=${test_vfs};i++)); do
						local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
						echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
						sleep 1e-06
						echo > /sys/bus/pci/devices/${vf_pci}/driver_override
						sleep 1e-06
						echo ${vf_pci} > /sys/bus/pci/drivers_probe
					done
					sleep 1e-06

					#7. set vf mtu
					echo "7. set vf mtu to ${MTU}"
					for ((i=1;i<=${test_vfs};i++)); do
						vf_name=${sort_vf_name_list[$(expr $i - 1)]}
						echo $MTU > /sys/class/net/${vf_name}/mtu
					done

					#8. set pf up if not already
					echo "8. set pf up if not already"

					ip link set ${nic_test} up
					echo "Iteration: xx $xx, yy $yy"
					echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
					sleep 1e-06
					echo "clean vf and reset mtu to 1500"
					ip link set mtu 1500 dev $nic_test

				done
			done
		fi
		rlLog "Check that the test ends in a normal loop"
		if [[ $(cat /tmp/sriov_test_reproduce_2021326_xx) -ne 3 ]] || [[ $(cat /tmp/sriov_test_reproduce_2021326_yy) -ne 10 ]]; then
			rlFail "The test did not end in a normal cycle. please check it!!!"
		fi

		sync_set server sriov_test_negative_create_vfs_2000180_end ${SYNC_TIME}
		rm -rf /tmp/sriov_test_reproduce_2021326
		rm -rf /tmp/sriov_test_reproduce_2021326_phase1
		rm -rf /tmp/sriov_test_reproduce_2021326_xx
		rm -rf /tmp/sriov_test_reproduce_2021326_yy
		rlLog "finish test and clean tag file"
		rlLog "check journald boot list"
		rlRun "journalctl --list-boots"
		local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
		rlLog "got prelate record id: ${prevlast}"
		rlRun "journalctl -o short-precise -k -b ${prevlast} | grep -C 50 -i \"call trace\"" 1
		rlLog "cleanup journald setting"
		rlRun "systemd-tmpfiles --clean --prefix /var/log/journal/"
		rlRun "systemd-tmpfiles --remove --prefix /var/log/journal/"
		rlRun "systemctl restart systemd-journald.service"
		rlLog "finish test and clean tag file"
#		local user=$(cat /etc/motd | grep SUBMITTER | awk -F "=" '{print $2}' | sed  's/\(.*\)@.*/\1/g')
#		local jobid=$(cat /etc/motd | grep JOBID | awk -F "=" '{print $2}' | tr -d '\n' | tr -d " ")
#		local kernel_version=$(uname -r)
#		local hostname=$(hostname)
#		rlLog "try to use jobid: ${jobid}, kernel verion: ${KERNEL_VERSION}, username: ${user}, hostname: ${hostname} to find vmcore"
#		local file_list=$(find /var/crash/${user}/${KERNEL_VERSION}/${jobid}/${hostname}/ -name vmcore*)
#		if [[ ${file_list} != "" ]]; then
#			rlFail "can find vmcore file, need to check"
#		else
#			rlLog "can't find vmcore"
#		fi
		return 0

	fi
}


sriov_test_reproduce_2021326_reboot_check()
{
	rlLog "Setup sriov_test_reproduce_2021326_reboot_check"
	if i_am_server; then
		sync_set client sriov_test_reproduce_2021326_reboot_check_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client sriov_test_reproduce_2021326_reboot_check_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		if [ ! -f /tmp/sriov_test_reproduce_2021326_reboot_check ]; then
			sync_wait server sriov_test_reproduce_2021326_reboot_check_start ${SYNC_TIME}
			rlLog "Start test"
			rlLog "Configure journalctl"
			[[ -d /var/log/journal ]] || mkdir /var/log/journal
			systemd-tmpfiles --create --prefix /var/log/journal
			echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
			systemctl restart systemd-journald.service
			rlLog "Configure finish"
			local DRIVER=$(ethtool -i $nic_test | sed -n -e "/driver:/s/driver: //p")
			rlLog "Test nic driver is ${DRIVER}"

			rlLog "Create 10 vfs and Check vf drive type"
			local PF_PCI=$(sriov_get_pf_bus_info ${nic_test} 0)
			local MAX_VFS=$(cat /sys/bus/pci/devices/${PF_PCI}/sriov_totalvfs)
			if [[ ${MAX_VFS} -le 10 ]]; then
				local test_vfs=${MAX_VFS}
			else
				local test_vfs=10
			fi
			rlLog "got pf pci address is ${PF_PCI}, got test vf number is ${test_vfs}"

			rlRun "sriov_remove_vfs ${nic_test} 0"
			rlLog "try to create ${test_vfs} vfs"
			rlRun "sriov_create_vfs ${nic_test} 0 ${test_vfs}"
			sleep 10

			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
			if [ -z ${vf_driver_name} ]; then
				rlFail "can't find vf driver"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_reboot_check_end
				exit 1
			fi

			rlLog "check all vfs are created"
			if [[ $? -ne 0 ]] || [[ x"$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn* | wc -l)" != x"${test_vfs}" ]]; then
				rlFail "create the test vf of pf failed"
				rlRun "sriov_remove_vfs ${nic_test} 0"
				sync_set server sriov_test_reproduce_2021326_reboot_check_end
				exit 1
			fi

			rlLog "check no mac adress is 00:00:00:00:00:00"
			for((i=0;i<$(expr $test_vfs); i++)); do
				local test_vf_mac=$(ip link show ${nic_test} | grep "vf $i" | awk '{print$4}')
				rlAssertNotEquals "check ${test_vf_mac} mac equal 00:00:00:00:00:00" ${test_vf_mac} "00:00:00:00:00:00"
			done

			rlLog "got all of vf name on a list"
			local vf_name_list
			for ((i=1;i<=${test_vfs};i++));do
				local VF_PCI=$(sriov_get_vf_bus_info ${nic_test} 0 $i)
				local VF_IFACE=$(sriov_get_vf_iface ${nic_test} 0 $i)
				vf_name_list[$(expr $i - 1)]=${VF_IFACE}
			done

			local sort_vf_name_list=($(echo ${vf_name_list[*]} | tr ' ' '\n'  | sort -n -t 'v' -k 2 ))

			local vf_mac_list
			for ((i=1;i<=${test_vfs};i++));do
				vf_mac_list[$(expr $i - 1)]=$(ip link show ${sort_vf_name_list[$(expr $i - 1)]} | grep "link/ether" | cut -d " " -f 6)
			done
			local vf_mac_list_length=${#vf_mac_list[@]}
			rlLog "got vf name after sort: ${sort_vf_name_list[*]}"
			rlLog "got vf mac list: ${vf_mac_list[*]}"
			rlLog "got vf mac length: ${vf_mac_list_length}"
			rlLog "clean all vf and start test"
			rlRun "echo 0 > /sys/class/net/${nic_test}/device/sriov_numvfs"

			rlLog "Beginning test"
			set -x
			local MTU=9000
			modprobe -r vfio-pci
			sleep 1
			modprobe -r vfio
			sleep 1
			modprobe vfio-pci
			sleep 1
			modprobe vfio
			sleep 1
			rmmod ${vf_driver_name}
			sleep 1

			# 1. set numvfs
			echo "1. set numvfs"
			echo "set ${test_vfs} vfs on ${nic_test}"
			echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
			echo ${test_vfs} > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
			sleep 5


			#2. set vf admin MAC address
			echo "2. set vf admin MAC address"
			for ((i=1;i<=${test_vfs};i++)); do
				local vf_mac=${vf_mac_list[$(expr $i - 1)]}
				ip link set dev $nic_test vf $(expr $i - 1) mac ${vf_mac}
			done


			# 3. unbind/bind vf driver
			echo "unbind/bind vf driver"
			for ((i=1;i<=${test_vfs};i++)); do
				local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
				echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
				echo > /sys/bus/pci/devices/${vf_pci}/driver_override
				echo ${vf_pci} > /sys/bus/pci/drivers_probe
			done

			# 4. set pf mtu
			echo "4. set pf mtu to ${MTU}"
			echo $MTU > /sys/class/net/${nic_test}/mtu

			#5. bind vf driver (if not already)
			#6. unbind/bind vf driver (workaround for bz1875338)
			echo "6. unbind/bind vf driver (workaround for bz1875338)"
			for ((i=1;i<=${test_vfs};i++)); do
				local vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn$(expr $i - 1) | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
				echo ${vf_pci} > /sys/bus/pci/drivers/${vf_driver_name}/unbind
				echo > /sys/bus/pci/devices/${vf_pci}/driver_override
				echo ${vf_pci} > /sys/bus/pci/drivers_probe
			done

			sleep 2

			#7. set vf mtu
			echo "7. set vf mtu to ${MTU}"
			for ((i=1;i<=${test_vfs};i++)); do
				vf_name=${sort_vf_name_list[$(expr $i - 1)]}
				echo $MTU > /sys/class/net/${vf_name}/mtu
			done


			#8. set pf up if not already
			echo "8. set pf up if not already"
			ip link set ${nic_test} up
			sleep 5
			echo "clean vf and reset mtu to 1500"
			echo 0 > /sys/bus/pci/devices/${PF_PCI}/sriov_numvfs
			sleep 5
			ip link set mtu 1500 dev $nic_test
			echo 1 > /tmp/sriov_test_reproduce_2021326_reboot_check
			rhts-reboot
		else
			rlLog "check journald boot list"
			rlRun "journalctl --list-boots"
			local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
			rlLog "got prelate record id: ${prevlast}"
			rlRun "journalctl -o short-precise -k -b ${prevlast} | grep -C 50 -i \"call trace\"" 1
			rlLog "cleanup journald setting"
			rlRun "systemd-tmpfiles --clean --prefix /var/log/journal/"
			rlRun "systemd-tmpfiles --remove --prefix /var/log/journal/"
			rlRun "systemctl restart systemd-journald.service"
			rlLog "finish test and clean tag file"
			rm -rf /tmp/sriov_test_reproduce_2021326_reboot_check

			sync_set server sriov_test_reproduce_2021326_reboot_check_end ${SYNC_TIME}
		fi
		return 0

	fi
}

sriov_test_vf_cfg_stress()
{
	#reproducer for bz1997012 bz1996954, cfg vf in loop, should just fail without a kernel panic
	ip link set $nic_test up
	if i_am_server; then
		sync_set client test_vf_cfg_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_vf_cfg_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		ip link set $nic_test up
		if [ ! -f /tmp/sriov_test_vf_cfg_stress ]; then
			sync_wait server test_vf_cfg_start ${SYNC_TIME}
			rlLog "start sriov_test_vf_cfg_stress test"
			echo 1 > /tmp/sriov_test_vf_cfg_stress
			if ! sriov_create_vfs $nic_test 0 1; then
				sync_set server test_vf_cfg_end ${SYNC_TIME}
				return 1
			fi

			local VF=$(sriov_get_vf_iface $nic_test 0 1)
			if [ -z "$VF" ]; then
				rlFail "FAIL to get VF interface"
				result=1
				sync_set server test_vf_cfg_end ${SYNC_TIME}
			else
				ethtool -i $VF
				change_vf_cfg_in_loop()
				{
					# clear dmesg
					dmesg -C
					sriov_remove_vfs $nic_test 0
					for ((i=0; i<500; i++)); do
						echo "create vf"
						ip link set $nic_test up
						sriov_create_vfs $nic_test 0 1
						# change vf cfg
						for i in `seq 0 100`;do
							ip link set $nic_test vf 0 trust on spoofchk on
							sleep 1
							ip link set $nic_test vf 0 trust off spoofchk off
							sleep 1
							ip link set $nic_test vf 0 trust on spoofchk on
							sleep 1
						done
						echo "remove vf"
						sriov_remove_vfs $nic_test 0
						dmesg | grep -i busy && return 1
					done
				}
				vf_in_netns()
				{
					# clear netns
					ip netns del ns1 &>/dev/null
					# create netns
					ip netns add ns1
					ip netns exec ns1 ip link add name br0 type bridge
					ip netns exec ns1 ip link set br0 up
					# vf option
					while :;do
						[ -z "$VF" ] && { continue; }
						echo "setup vf in netns"
						ip link set $VF address "22:00:01:02:03:04" && echo "set mac succeeded 1"
						ip link set $VF netns ns1
						ip netns exec ns1 ip link set $VF up
						ip netns exec ns1 ip link set $VF master br0
						ip netns exec ns1 ip link set $VF address "22:00:01:02:03:05" && echo "set mac succeeded 2"
						ip netns exec ns1 ip link set $VF netns 1
					done
					# remove netns
					ip netns del ns1
				}
				(
					change_vf_cfg_in_loop &
					local child2=$!
					vf_in_netns &
					local child1=$!
					trap -- "" SIGTERM
					(
						sleep 3600
						kill $child1 2> /dev/null
						kill $child2 2> /dev/null
					) &
					wait $child1
					wait $child2
				)
				sync_set server test_vf_cfg_end ${SYNC_TIME}
			fi
			sriov_remove_vfs $nic_test 0
		else
			rlLog "finish sriov_test_vf_cfg_stress and clean tag file"
			rm -rf /tmp/sriov_test_vf_cfg_stress
			sriov_remove_vfs $nic_test 0
			sync_set server test_vf_cfg_end ${SYNC_TIME}
		fi
	fi
}

sriov_test_2049237_VF_mac_reset_zero()
{
	if i_am_server ; then
		sync_set client test_VF_mac_reset_zero_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_VF_mac_reset_zero_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else

		if [ ! -f /tmp/sriov_test_2049237_VF_mac_reset_zero ]; then
			# configure hugepage before start test.
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=12" /proc/cmdline &>/dev/null)
			then
				rlLog "grubby --args=\"default_hugepagesz=2G hugepagesz=2G hugepages=12\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=2G hugepagesz=2G hugepages=12" --update-kernel=$(grubby --default-kernel)
				rhts-reboot
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
				rhts-reboot
			else
				rlLog "client finish hugepage configuration"
			fi

			sync_wait server test_VF_mac_reset_zero_start ${SYNC_TIME}

			echo 1 > /tmp/sriov_test_2049237_VF_mac_reset_zero
			rpm -q dpdk || yum install -y dpdk 2>/dev/null || rlFail "install dpdk failed"
			rpm -q dpdk-tools || yum install -y dpdk-tools 2>/dev/null || rlFail "install dpdk failed"

			modprobe -r vfio-pci
			sleep 1
			modprobe -r vfio
			sleep 1
			modprobe vfio-pci
			sleep 1
			modprobe vfio
			sleep 1

			ip link set $nic_test up
			sriov_create_vfs ${nic_test} 0 8 || { rlFail "Create vf failed on ${nic_test}"; sync_set server test_VF_mac_reset_zero_end; }
			ip link show ${nic_test}
			local dpdk_devbind_path=$(rpm -ql dpdk-tools | grep devbind.py$)
			local testpmd_cmd=$(rpm -ql dpdk | grep testpmd$)
			local vf1_name=$(sriov_get_vf_iface ${nic_test} 0 1)
			local vf2_name=$(sriov_get_vf_iface ${nic_test} 0 2)
			local vf1_pci=$(sriov_get_vf_bus_info ${nic_test} 0 1)
			local vf2_pci=$(sriov_get_vf_bus_info ${nic_test} 0 2)

			$dpdk_devbind_path --status
			ip link set ${vf1_name} down
			ip link set ${vf2_name} down
			local driver_name=$(ethtool -i ${nic_test}| grep driver | awk '{print $NF}')
			if [[ ${driver_name} =~ mlx.* ]]; then
				echo "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf1_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			# workaround https://bugzilla.redhat.com/show_bug.cgi?id=2128171
			rlLog "full of testpmd cmd is: \"${testpmd_cmd} -a ${vf1_pci} -a ${vf2_pci} -n 4 --iova-mode=va -- -i --nb-cores=1 --forward-mode=mac --port-topology=loop --no-mlockall\""
			nohup sh -c "(while sleep 1; do echo show port info all; done | ${testpmd_cmd} -a ${vf1_pci} -a ${vf2_pci} -n 4 --iova-mode=va -- -i --nb-cores=1 --forward-mode=mac --port-topology=loop --no-mlockall) &>/tmp/testpmd.log &"
			sleep 10
			sed -n '1,500p' /tmp/testpmd.log
			while [[ $(ps -aux | grep testpmd | grep -v "grep" | wc -l) -ne 0 ]]; do
				pkill -9 testpmd
				sleep 5
			done

			ip link show ${nic_test}

			local vf1_mac=$(ip link show ${nic_test} | grep "vf 0" | awk '{print$4}')
			local vf2_mac=$(ip link show ${nic_test} | grep "vf 1" | awk '{print$4}')
			rlAssertNotEquals "check ${vf1_name} mac equal 00:00:00:00:00:00" ${vf1_mac} "00:00:00:00:00:00"
			rlAssertNotEquals "check ${vf2_name} mac equal 00:00:00:00:00:00" ${vf2_mac} "00:00:00:00:00:00"

			if [[ ${driver_name} =~ mlx.* ]]; then
				echo "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf1_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			sriov_remove_vfs ${nic_test} 0
			rm -rf /tmp/sriov_test_2049237_VF_mac_reset_zero
			sync_set server test_VF_mac_reset_zero_end ${SYNC_TIME}
		else
			rm -rf /tmp/sriov_test_2049237_VF_mac_reset_zero
			sync_set server test_VF_mac_reset_zero_end ${SYNC_TIME}
		fi
	fi

}

sriov_test_2049237_VF_mac_reset_zero_reboot_check()
{
	if i_am_server ; then
		sync_set client test_VF_mac_reset_zero_reboot_check_start ${SYNC_TIME}
		if	[ $? -eq 0 ]; then
			sync_wait client test_VF_mac_reset_zero_reboot_check_end ${SYNC_TIME}
		else
			rlFail "sync timeout with client. Need check it!!!"
		fi
	else
		# after do test, need reboot to check whether call trace occurred.
		if [ ! -f /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check ]; then
			# configure hugepage before start test.
			if [ "$SYS_ARCH" == "ppc64le" ] && (! grep "default_hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=2G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null)
			then
				rlLog "grubby --args=\"default_hugepagesz=2G hugepagesz=2G hugepages=24\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=2G hugepagesz=2G hugepages=24" --update-kernel=$(grubby --default-kernel)
				rhts-reboot
			elif [ "$SYS_ARCH" != "ppc64le" ] && (! grep "default_hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepagesz=1G" /proc/cmdline &>/dev/null || \
			! grep "hugepages=24" /proc/cmdline &>/dev/null || \
			! grep "intel_iommu=on" /proc/cmdline &>/dev/null || \
			! grep "iommu=pt" /proc/cmdline &>/dev/null)
			then
				# set nosmt=force and default hugepage in host
				rlLog "grubby --args=\"default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt\" --update-kernel=$(grubby --default-kernel)"
				grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24 intel_iommu=on iommu=pt" --update-kernel=$(grubby --default-kernel)
				rhts-reboot
			else
				rlLog "client finish hugepage configuration"
			fi

			rlLog "Configure journalctl"
			[[ -d /var/log/journal ]] || mkdir /var/log/journal
			systemd-tmpfiles --create --prefix /var/log/journal
			echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
			systemctl restart systemd-journald.service
			rlLog "Configure finish"
			rpm -q dpdk || yum install -y dpdk 2>/dev/null || rlFail "install dpdk failed"
			rpm -q dpdk-tools || yum install -y dpdk-tools 2>/dev/null || rlFail "install dpdk failed"

			rlRun "modprobe -r vfio-pci"
			sleep 1
			rlRun "modprobe -r vfio"
			sleep 1
			rlRun "modprobe vfio-pci"
			sleep 1
			rlRun "modprobe vfio"
			sleep 1
			rlRun "lsmod | grep vfio"
			rlRun "ip link set $nic_test up"
			sriov_create_vfs ${nic_test} 0 8 || { rlFail "Create vf failed on ${nic_test}"; sync_set server test_VF_mac_reset_zero_reboot_check_end; }
			rlRun "ip link show ${nic_test}"
			local dpdk_devbind_path=$(rpm -ql dpdk-tools | grep devbind.py$)
			local testpmd_cmd=$(rpm -ql dpdk | grep testpmd$)
			local vf1_name=$(sriov_get_vf_iface ${nic_test} 0 1)
			local vf2_name=$(sriov_get_vf_iface ${nic_test} 0 2)
			local vf1_pci=$(sriov_get_vf_bus_info ${nic_test} 0 1)
			local vf2_pci=$(sriov_get_vf_bus_info ${nic_test} 0 2)

			rlRun "$dpdk_devbind_path --status"
			rlRun "ip link set ${vf1_name} down"
			rlRun "ip link set ${vf2_name} down"
			local driver_name=$(ethtool -i ${nic_test}| grep driver | awk '{print $NF}')
			if [[ ${driver_name} =~ mlx.* ]]; then
				rlLog "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf1_pci"
				rlRun "$dpdk_devbind_path -b vfio-pci $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			local dpdk_version=$(rpm -q --queryformat '%{VERSION}' dpdk-tools | awk -F '.' '{print $1}')
			if (( ${dpdk_version} > 20 )); then
				local allow_list_option='-a'
			else
				local allow_list_option='-w'
			fi
			nohup sh -c "(while sleep 1; do echo show port info all; done | ${testpmd_cmd} ${allow_list_option} ${vf1_pci} ${allow_list_option} ${vf2_pci} -n 4 --iova-mode=va -- -i --nb-cores=5 --forward-mode=mac --port-topology=loop --no-mlockall) &>/tmp/testpmd.log &"
			sleep 10
			sed -n '1,500p' /tmp/testpmd.log
			while [[ $(ps -aux | grep testpmd | grep -v "grep" | wc -l) -ne 0 ]]; do
				pkill -9 testpmd
				sleep 5
			done

			ip link show ${nic_test}

			local vf1_mac=$(ip link show ${nic_test} | grep "vf 0" | awk '{print$4}')
			local vf2_mac=$(ip link show ${nic_test} | grep "vf 1" | awk '{print$4}')
			rlAssertNotEquals "check ${vf1_name} mac equal 00:00:00:00:00:00" ${vf1_mac} "00:00:00:00:00:00"
			rlAssertNotEquals "check ${vf2_name} mac equal 00:00:00:00:00:00" ${vf2_mac} "00:00:00:00:00:00"

			if [[ ${driver_name} =~ mlx.* ]]; then
				rlLog "test nic belong to mlx, do nothing"
			else
				rlRun "$dpdk_devbind_path -u $vf1_pci"
				rlRun "$dpdk_devbind_path -u $vf2_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf1_pci"
				rlRun "$dpdk_devbind_path -b iavf $vf2_pci"
				rlRun "$dpdk_devbind_path --status"
			fi
			sync_wait server test_VF_mac_reset_zero_reboot_check_start ${SYNC_TIME}
			sriov_remove_vfs ${nic_test}
			echo "1" > /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check
			rhts-reboot
		else
			rlLog "check journald boot list"
			rlRun "journalctl --list-boots"
			local prevlast=$(journalctl --list-boots | awk '{prevlast = last; last = $0} END {if (NR >= 2) print prevlast}' | awk '{print $1}')
			rlLog "got prelate record id: ${prevlast}"
			rlRun "journalctl -o short-precise -k -b ${prevlast} | grep -C 100 -i \"call trace\"" 1
			rlLog "cleanup journald setting"
			rlRun "systemd-tmpfiles --clean --prefix /var/log/journal/"
			rlRun "systemd-tmpfiles --remove --prefix /var/log/journal/"
			rlRun "systemctl restart systemd-journald.service"
			rm -rf /tmp/sriov_test_2049237_VF_mac_reset_zero_reboot_check
			sync_set server test_VF_mac_reset_zero_reboot_check_end ${SYNC_TIME}
		fi
	fi
}

sriov_test_reproduce_2057244_and_2070917_ns(){
	# for 2057244 should got Invalid message from VF 0, opcode 3, len 4, error -1
	# for 2070917 should ping failed when first time. ip netns exec sriov_test_reproduce_2057244_ns ping -c3 172.3.${ipaddr}.188

	if i_am_server; then
		sync_set client sriov_test_reproduce_2057244_and_2070917_ns_start
		if [ $? -eq 0 ]; then
			local test_nic=$(get_test_nic)
			rlLog "test nic is: ${test_nic}"
			rlRun "ip link set ${test_nic} up"
			rlRun "ip link add link ${test_nic} name ${test_nic}.3 type vlan id 3" # can use random vlan
			rlRun "ip addr add 172.3.${ipaddr}.188/24 dev ${test_nic}.3" # can use random vlan
			rlRun "ip link set ${test_nic}.3 up" # can use random IP address
			nohup ping -I ${test_nic}.3 172.3.${ipaddr}.111 &
			sync_wait client sriov_test_reproduce_2057244_and_2070917_ns_end
			if [ $? -eq 0 ]; then
				rlLog "finish sriov_test_reproduce_2057244_ns"
			else
				rlFail "sync error need to check"
			fi
			pkill -9 ping
			ip addr flush ${test_nic}.3
			ip link del ${test_nic}.3
		else
			rlFail "sync error need to check"
			exit 1
		fi
	else
		sync_wait server sriov_test_reproduce_2057244_and_2070917_ns_start
		if [ $? -eq 0 ]; then
			local test_nic=$(get_test_nic)
			local random_mac=$(get_mac_prefix $(hostname))
			local vf_mac="${random_mac}02:02"
			rlLog "got vf randon mac is: ${vf_mac}"
			rlRun "ip link set ${test_nic} up"
			rlLog "test nic is: ${test_nic}"
			rlLog "try to got vf0 name"
			local PF_PCI=$(sriov_get_pf_bus_info ${test_nic} 0)
			rlRun "echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs"
			rlLog "try to create 1 vfs"
			rlRun "echo 1 > /sys/class/net/${test_nic}/device/sriov_numvfs"
			sleep 10
			local check_vf_pci=$(ls -l /sys/bus/pci/devices/${PF_PCI}/virtfn0 | awk '{print $NF}' | sed 's/..\///' | sed -n 1p)
			local check_vf_name=$(ls /sys/bus/pci/devices/${check_vf_pci}/net 2>/dev/null)
			rlLog "got vf 0 name is: ${check_vf_name}"
			rlRun "echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs"
			sleep 10
			for i in $(seq 1 100); do
				rlLog "start $i test"
				modprobe -r bridge
				echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs
				ip li > /dev/null
				echo 8 > /sys/class/net/${test_nic}/device/sriov_numvfs
				sleep 3
				ip link set ${test_nic} vf 0 vlan 3
				ip netns add sriov_test_reproduce_2057244_ns
				ip link set dev ${check_vf_name} netns sriov_test_reproduce_2057244_ns
				ip netns exec sriov_test_reproduce_2057244_ns ip link add dev br0 type bridge
				ip netns exec sriov_test_reproduce_2057244_ns ip link set ${check_vf_name} master br0
				ip netns exec sriov_test_reproduce_2057244_ns ip link set ${check_vf_name} up
				ip netns exec sriov_test_reproduce_2057244_ns ip link set br0 up
				ip netns exec sriov_test_reproduce_2057244_ns ip addr flush br0
				ip netns exec sriov_test_reproduce_2057244_ns ip addr add 172.3.${ipaddr}.111/24 dev br0 # can use random IP address
				ip netns exec sriov_test_reproduce_2057244_ns ping -c3 172.3.${ipaddr}.188 || {
					rlFail "Ping failed when run $i cycle"
				}
				ip link set ${test_nic} vf 0 mac ${vf_mac}
				ip netns exec sriov_test_reproduce_2057244_ns ip link set br0 address ${vf_mac}
				ip netns exec sriov_test_reproduce_2057244_ns ping -c3 172.3.${ipaddr}.188 || {
					rlFail "Ping failed when run $i cycle"
				}
				ip link set ${test_nic} vf 0 vlan 0
				ip link set ${test_nic} vf 0 trust on
				ip link set ${test_nic} vf 0 trust off
				ip link set ${test_nic} vf 0 trust on
				ip link set ${test_nic} vf 0 trust off
				ip link set ${test_nic} vf 0 trust on
				ip netns exec sriov_test_reproduce_2057244_ns ip addr flush br0
				ip netns exec sriov_test_reproduce_2057244_ns ip link add link br0 name br0.3 type vlan id 3
				ip netns exec sriov_test_reproduce_2057244_ns ip link set br0.3 up
				ip netns exec sriov_test_reproduce_2057244_ns ip addr add 172.3.${ipaddr}.111/24 dev br0.3 # can use random IP address
				ip netns exec sriov_test_reproduce_2057244_ns ping -c5 172.3.${ipaddr}.188 || {
					rlFail "Ping failed when run $i cycle"
					rlRun "ip netns exec sriov_test_reproduce_2057244_ns ip link show"
					rlRun "ip netns exec sriov_test_reproduce_2057244_ns ip link show | grep -w NO-CARRIER" "1-255"
					break
				}
				rlLog "finish $i test"
				ip netns del sriov_test_reproduce_2057244_ns
			done
			rlLog "clean test configuration"
			rlRun "ip netns del sriov_test_reproduce_2057244_ns" "0,1"
			rlRun "echo 0 > /sys/class/net/${test_nic}/device/sriov_numvfs"
			sync_set server sriov_test_reproduce_2057244_and_2070917_ns_end
		else
			rlFail "sync error with server"
			exit 1
		fi
	fi
}
sriov_test_bz2008373() {
		if i_am_server ; then
			sync_set client sriov_test_bz2008373_start  52200
			sync_wait client sriov_test_bz2008373_end 52200
		else
			sync_wait server sriov_test_bz2008373_start  52200
			rlLog "start to test sriov_test_bz2008373_start"
			local nic_name=$(get_test_nic 1)
			PCI=$(ethtool -i ${nic_name} | grep bus | cut -d " " -f 2)
			vf_max_num=$(cat /sys/class/net/${nic_name}/device/sriov_totalvfs)
			[ ${vf_max_num} -lt 64 ] && vf_num=${vf_max_num} || vf_num=64
			echo  ${vf_num} > /sys/bus/pci/devices/$PCI/sriov_numvfs
			loop_num=$(expr ${vf_num} - 1)
			for VF in $(seq 0 ${loop_num})
			do
				echo "loop time: $VF"
				vf="vf$VF"
				echo "vf name: $vf"
				for i in {1..10001}
				do
						{ ip link set ${nic_name} vf $VF trust on;ip link set ${nic_name} vf $VF vlan 10 qos 1;ip link set ${nic_name} vf $VF vlan 0 qos 0; }
						[ $? -ne 0 ] && echo "bug occur" && result=1 && break 2
				done
			done
			ip -d link show ${nic_name}
			echo 0 > /sys/bus/pci/devices/$PCI/sriov_numvfs

			sync_set server sriov_test_bz2008373_end  52200
		fi
		return $result
}

# vf_intf_garp_check is for bz1938635
vf_intf_garp_check() {
	rlLog "vf_intf_garp_check is for bz1938635"
	result=0
	if i_am_server; then
		sync_set client vf_intf_garp_check_start
		sync_wait client vf_intf_garp_check_end
	else
		rlLog "start to test client vf_intf_arp_check"
		sync_wait server vf_intf_garp_check_start
		local nic_test=$(get_test_nic 1)
		PF_PCI=$(ethtool -i ${nic_test} | grep bus | cut -d " " -f 2)
		#1.enable sriov
		rlLog "STEP 1: Enable sriov on client"
		sriov_create_vfs ${nic_test} 0 1
		sleep 3
		#2. set ip addr for vf
		rlLog "STEP 2: Set IP address for vf interface"
		local VF_IFACE=$(sriov_get_vf_iface $nic_test 0 1)
		ip addr add 172.30.${ipaddr}.2/24 dev ${VF_IFACE}
		ip link set $VF_IFACE up
		#3.set arp_notify for GARP
		rlLog "STEP 3: Set arp_notify for PF and vf"
		pf_garp_status=$(cat /proc/sys/net/ipv4/conf/${nic_test}/arp_notify)
		vf_garp_status=$(cat /proc/sys/net/ipv4/conf/${VF_IFACE}/arp_notify)
		[ ${pf_garp_status} -eq 0 ] && echo 1 > /proc/sys/net/ipv4/conf/${nic_test}/arp_notify
		[ ${vf_garp_status} -eq 0 ] && echo 1 > /proc/sys/net/ipv4/conf/${VF_IFACE}/arp_notify
		#4. set effective mac for vf and check the effective mac address whether be applied
		rlLog "STEP 4: set effective mac for vf , then check the effective mac address whether be applied, and if the garp packets are sent"
		vf_mac=00:11:22:33:44:10
		timeout 20  tcpdump -Q out  -nn -e  -i  ${VF_IFACE} arp  -w 1.pcap &
		sleep 8
		ip link set ${VF_IFACE} addr ${vf_mac}
		sleep 13
		ip link show ${VF_IFACE} | grep -i  ${vf_mac}
		[ $? -eq 0 ] ||  { result=1; rlFail "step 4: configure link mac ${vf_mac} failed"; ip link show ${VF_IFACE}; }
		#check the GARP packets
		tcpdump -r 1.pcap -enn | grep  -i  "${vf_mac} > ff:ff:ff:ff:ff:ff"
		[ $? -eq 0 ] || { result=1; tcpdump -r 1.pcap -enn; rlFail "step 4: No garp packets captured for mac ${vf_mac}"; }
		#5.  set the admin mac for vf and check the mac when nic_driver= ice or i40e
		if  [ "$NIC_DRIVER" = "ice" ] || [ "$NIC_DRIVER" = "i40e" ]; then

			rlLog "STEP 5: Set the admin mac for vf and check if the mac is set successfully"
			vf_mac1=00:11:22:33:44:11
			ip link set ${nic_test} vf 0 mac ${vf_mac1}
			sleep 3
			ip link show ${VF_IFACE} | grep -i  ${vf_mac1}
			[ $? -eq 0 ] ||  { result=1; rlFail "${vf_mac1} : configure link mac failed"; ip link show ${VF_IFACE}; }

			#6.set the effective mac for vf
			rlLog "STEP 6: Set mac for vf interface and check if the mac is set successfully"
			vf_mac2=00:11:22:33:44:12
			info=$(ip link set ${VF_IFACE} addr ${vf_mac2} 2>&1)
			[[ $info == "RTNETLINK answers: Permission denied" ]] || { result=1; rlFail "There should be error info"; rlLog "The current info is $info"; }
			sleep 3
			ip link show ${VF_IFACE} | grep -i  ${vf_mac2}
			[ $? -ne 0 ] ||  { result=1; rlFail "step6 : configure link mac ${vf_mac2} should  fail"; ip link show ${VF_IFACE}; }
		fi
		sriov_remove_vfs $nic_test 0
		sync_set server  vf_intf_garp_check_end
	fi
	return $result
}


sriov_test_vlan_qinq_baisc()
{
	log_header "sriov_test_vlan_qinq_baisc" $result_file
	local result=0
	local test_name=sriov_test_vlan_qinq_baisc
	local outer_tag=30
	local inner_tag=31
	local server_outer_ip4="192.30.${ipaddr}.1"
	local server_outer_ip6="2021:db30:${ipaddr}:2345::1"
	local server_inner_ip4="172.31.${ipaddr}.1"
	local server_inner_ip6="2021:3130:${ipaddr}:2345::1"
	local server_inner_sametag_ip4="172.30.${ipaddr}.1"
	local server_inner_sametag_ip6="2021:3030:${ipaddr}:2345::1"
	local server_ip4="192.100.${ipaddr}.1"
	local server_ip6="2021:db08:${ipaddr}:2345::1"
	local vf_outer_ip4="192.30.${ipaddr}.2"
	local vf_outer_ip6="2021:db30:${ipaddr}:2345::2"
	local vf_inner_ip4="172.31.${ipaddr}.2"
	local vf_inner_ip6="2021:3130:${ipaddr}:2345::2"
	local vf_inner_sametag_ip4="172.30.${ipaddr}.2"
	local vf_inner_sametag_ip6="2021:3030:${ipaddr}:2345::2"
	local vf_ip4="192.100.${ipaddr}.2"
	local vf_ip6="2021:db08:${ipaddr}:2345::2"
	local ip4_mask_len="24"
	local ip6_mask_len="64"

	ip link set $nic_test up

	if i_am_server;then
		ip addr add ${server_ip4}/${ip4_mask_len} dev $nic_test
		ip addr add ${server_ip6}/${ip6_mask_len} dev $nic_test
		ip link add link $nic_test name $nic_test.$outer_tag type vlan id $outer_tag
		ip link add link $nic_test.$outer_tag name $nic_test.$outer_tag.$inner_tag type vlan id $inner_tag
		ip link add link $nic_test.$outer_tag name $nic_test.$outer_tag.$outer_tag type vlan id $outer_tag
		ip link set $nic_test.$outer_tag up
		ip link set $nic_test.$outer_tag.$inner_tag up
		ip link set $nic_test.$outer_tag.$outer_tag up
		ip addr add ${server_outer_ip4}/${ip4_mask_len} dev $nic_test.$outer_tag
		ip addr add ${server_outer_ip6}/${ip6_mask_len} dev $nic_test.$outer_tag
		ip addr add ${server_inner_ip4}/${ip4_mask_len} dev $nic_test.$outer_tag.$inner_tag
		ip addr add ${server_inner_ip6}/${ip6_mask_len} dev $nic_test.$outer_tag.$inner_tag
		ip addr add ${server_inner_sametag_ip4}/${ip4_mask_len} dev $nic_test.$outer_tag.$outer_tag
		ip addr add ${server_inner_sametag_ip6}/${ip6_mask_len} dev $nic_test.$outer_tag.$outer_tag
		sync_set client 8100_over_8100_start
		sync_wait client 8100_over_8100_end
		rlRun "get_iface_sw_port $nic_test sw port"
		if [ `echo $sw |grep 5200` ]; then
			# juniper 5200 don't support 88a8 and 8100 at the same time. let 88a8 pass
			rlRun "swcfg set_interface_88a8 $sw $port"
		fi
		ip link delete $nic_test.$outer_tag.$inner_tag
		ip link delete $nic_test.$outer_tag.$outer_tag
		ip link delete $nic_test.$outer_tag
		ip link add link $nic_test name $nic_test.$outer_tag type vlan id $outer_tag protocol 802.1ad
		ip link add link $nic_test.$outer_tag name $nic_test.$outer_tag.$inner_tag type vlan id $inner_tag
		ip link add link $nic_test.$outer_tag name $nic_test.$outer_tag.$outer_tag type vlan id $outer_tag
		ip link set $nic_test.$outer_tag up
		ip link set $nic_test.$outer_tag.$inner_tag up
		ip link set $nic_test.$outer_tag.$outer_tag up
		ip addr add ${server_outer_ip4}/${ip4_mask_len} dev $nic_test.$outer_tag
		ip addr add ${server_outer_ip6}/${ip6_mask_len} dev $nic_test.$outer_tag
		ip addr add ${server_inner_ip4}/${ip4_mask_len} dev $nic_test.$outer_tag.$inner_tag
		ip addr add ${server_inner_ip6}/${ip6_mask_len} dev $nic_test.$outer_tag.$inner_tag
		ip addr add ${server_inner_sametag_ip4}/${ip4_mask_len} dev $nic_test.$outer_tag.$outer_tag
		ip addr add ${server_inner_sametag_ip6}/${ip6_mask_len} dev $nic_test.$outer_tag.$outer_tag
		sync_set client 8100_over_88a8_start

		sync_wait client 8100_over88a8_end
		if [ `echo $sw |grep 5200` ]; then
			# juniper 5200 don't support 88a8 and 8100 at the same time. delete 88a8 config to let 8100 pass
			rlRun "swcfg del_interface_88a8 $sw $port"
		fi
		ip link delete $nic_test.$outer_tag.$inner_tag
		ip link delete $nic_test.$outer_tag.$outer_tag
		ip link delete $nic_test.$outer_tag
		return 0
	else
#if [ "$NIC_DRIVER" = "i40e" ] || [ "$NIC_DRIVER" = "ice" ];then
		if [ "$NIC_DRIVER" = "ice" ];then
			sync_wait server 8100_over_8100_start
			local mac="00:de:ad:$(printf %02x $ipaddr):01:01"
			if ! sriov_create_vfs $nic_test 0 2; then
				echo "create vf failed"
				sync_set server 8100_over_8100_end
				sync_wait server 8100_over_88a8_start
				sync_set server 8100_over_88a8_end
				return 1
			fi

			if ! sriov_attach_vf_to_vm $nic_test 0 1 $vm1 $mac; then
				echo "attach vf to vm failed"
				sriov_remove_vfs $nic_test 0
				sync_set server 8100_over_8100_end
				sync_wait server 8100_over_88a8_start
				sync_set server 8100_over_88a8_end
				return 1
		else
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$inner_tag type vlan id $inner_tag}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$outer_tag type vlan id $outer_tag}
				{ip link set \$NIC_TEST.$outer_tag up}
				{ip link set \$NIC_TEST.$inner_tag up}
				{ip addr add  $vf_outer_ip4/${ip4_mask_len} dev \$NIC_TEST}
				{ip addr add  $vf_outer_ip6/${ip6_mask_len} dev \$NIC_TEST}
				{ip addr add  $vf_inner_ip4/${ip4_mask_len} dev \$NIC_TEST.$inner_tag}
				{ip addr add  $vf_inner_ip6/${ip6_mask_len} dev \$NIC_TEST.$inner_tag}
				{ip addr add  $vf_inner_sametag_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr add  $vf_inner_sametag_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr show }

			)

			ip link set $nic_test vf 0 vlan $outer_tag
			vmsh cmd_set $vm1 "${cmd[*]}"

			echo "vf vlan 8100====================================================================================================================="

			if ! do_vm_netperf $vm1 $server_outer_ip4 $server_outer_ip6 $result_file;then
				result+=1
				echo "single_outer_tag(8100) $outer_tag vf_outer_ip netperf failed"
			fi

			local cmd=(
				{ping -c 10 $server_inner_ip4 }
				{ping -c 10 $server_inner_sametag_ip4}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				rlFail "fail:ping failed via vf  qinq(8100_over_8100)"
			fi

:<<!
			#do not run netperf cause bug 2102931
			if ! do_vm_netperf $vm1 $server_inner_ip4 $server_inner_ip6 $result_file;then
				result += 1
				echo "double_inner_outer_tag(8100_over_8100) $inner_tag over $outer_tag vf_innter_ip netperf failed"
			fi

			if ! do_vm_netperf $vm1 $server_inner_sametag_ip4 $server_inner_sametag_ip6 $result_file; then
				result +=1
				echo "double_outer_outer_tag(8100_over_8100) $outer_tag over $outer_tag vf_inner_sametag_ip netperf failed"
			fi
!

			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ethtool -K \$NIC_TEST rxvlan off}
				{ethtool -K \$NIC_TEST txvlan off}
				{ethtool -K \$NIC_TEST tx-vlan-stag-hw-insert on}
				{ethtool -K \$NIC_TEST rx-vlan-stag-hw-parse on}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			if ! do_vm_netperf $vm1 $server_outer_ip4 $server_outer_ip6 $result_file;then
				result+=1
				echo "qinq_offload on single_outer_tag(8100) $outer_tag vf_outer_ip netperf failed"
			fi

			local cmd=(
				{ping -c 10 $server_inner_ip4 }
				{ping -c 10 $server_inner_sametag_ip4}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				rlFail "fail:ping failed via offload on vf qinq(8100_over_8100)"
			fi

:<<!
			#do not run the test , cause bug 2102931
			if ! do_vm_netperf $vm1 $server_inner_ip4 $server_inner_ip6 $result_file;then
				result += 1
				echo "qinq_offload on double_inner_outer_tag(8100_over_8100) $inner_tag over $outer_tag vf_innter_ip netperf failed"
			fi

			if ! do_vm_netperf $vm1 $server_inner_sametag_ip4 $server_inner_sametag_ip6 $result_file; then
				result +=1
				echo "qinq_offload on double_outer_outer_tag(8100_over_8100) $outer_tag over $outer_tag vf_inner_sametag_ip netperf failed"
			fi
!

			ip link set $nic_test vf 0 vlan 0
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link delete \$NIC_TEST.$inner_tag}
				{ip link delete \$NIC_TEST.$outer_tag}
				{ip add flush \$NIC_TEST}
				{ethtool -K \$NIC_TEST rxvlan on}
				{ethtool -K \$NIC_TEST txvlan on}
				{ethtool -K \$NIC_TEST tx-vlan-stag-hw-insert off}
				{ethtool -K \$NIC_TEST rx-vlan-stag-hw-parse off}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$outer_tag type vlan id $outer_tag}
				{ip link add link \$NIC_TEST.$outer_tag name \$NIC_TEST.$outer_tag.$inner_tag type vlan id $inner_tag}
				{ip link add link \$NIC_TEST.$outer_tag name \$NIC_TEST.$outer_tag.$outer_tag type vlan id $outer_tag}
				{ip link set \$NIC_TEST.$outer_tag up}
				{ip link set \$NIC_TEST.$outer_tag.$inner_tag up}
				{ip link set \$NIC_TEST.$outer_tag.$outer_tag up}
				{ip addr add  $vf_outer_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr add  $vf_outer_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr add  $vf_inner_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag.$inner_tag}
				{ip addr add  $vf_inner_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag.$inner_tag}
				{ip addr add  $vf_inner_sametag_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag.$outer_tag}
				{ip addr add  $vf_inner_sametag_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag.$outer_tag}
				{ip addr show }
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			echo "image_vm vlan 8100=================================================================================================================================================================="
			if ! do_vm_netperf $vm1 $server_outer_ip4 $server_outer_ip6 $result_file;then
				result+=1
				echo "vm_qinq single_outer_tag(8100) $outer_tag vf_outer_ip netperf failed"
			fi

			local cmd=(
				{ping -c 10 $server_inner_ip4 }
				{ping -c 10 $server_inner_sametag_ip4}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				rlFail "fail:ping failed via vm_qinq(8100_over_8100)"
			fi

:<<!
			if ! do_vm_netperf $vm1 $server_inner_ip4 $server_inner_ip6 $result_file;then
				result += 1
				echo "vm_qinq double_inner_outer_tag(8100_over_8100) $inner_tag over $outer_tag vf_innter_ip netperf failed"
			fi

			if ! do_vm_netperf $vm1 $server_inner_sametag_ip4 $server_inner_sametag_ip6 $result_file; then
				result +=1
				echo "vm_qinq double_outer_outer_tag(8100_over_8100) $outer_tag over $outer_tag vf_inner_sametag_ip netperf failed"
			fi
!

			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link delete \$NIC_TEST.$outer_tag.$inner_tag}
				{ip link delete \$NIC_TEST.$outer_tag.$outer_tag}
				{ip link delete \$NIC_TEST.$outer_tag}
			)

			vmsh cmd_set $vm1 "${cmd[*]}"


			sync_set server 8100_over_8100_end
			sync_wait server 8100_over_88a8_start

			rlRun "get_iface_sw_port $nic_test sw port"
			if [ `echo $sw |grep 5200` ]; then
				# 88a8 and 8100 don't support at the same time. let 88a8 pass
				rlRun "swcfg set_interface_88a8 $sw $port"
			fi
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link set \$NIC_TEST up}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$inner_tag type vlan id $inner_tag}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$outer_tag type vlan id $outer_tag}
				{ip link set \$NIC_TEST.$outer_tag up}
				{ip link set \$NIC_TEST.$inner_tag up}
				{ip addr add  $vf_outer_ip4/${ip4_mask_len} dev \$NIC_TEST}
				{ip addr add  $vf_outer_ip6/${ip6_mask_len} dev \$NIC_TEST}
				{ip addr add  $vf_inner_ip4/${ip4_mask_len} dev \$NIC_TEST.$inner_tag}
				{ip addr add  $vf_inner_ip6/${ip6_mask_len} dev \$NIC_TEST.$inner_tag}
				{ip addr add  $vf_inner_sametag_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr add  $vf_inner_sametag_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr show }
			)

			ip link set $nic_test vf 0 vlan $outer_tag proto 802.1ad
			vmsh cmd_set $vm1 "${cmd[*]}"

			echo "vf vlan 88a8============================================================================================================================================="
			if ! do_vm_netperf $vm1 $server_outer_ip4 $server_outer_ip6 $result_file; then
				result+=1
				echo "single_outer_tag(88a8) $outer_tag vf_outer_ip netperf failed"
			fi

			local cmd=(
				{ping -c 10 $server_inner_ip4 }
				{ping -c 10 $server_inner_sametag_ip4}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				rlFail "fail:ping failed via vf  qinq(8100_over_88a8)"
			fi

:<<!
			if ! do_vm_netperf $vm1 $server_inner_ip4 $server_inner_ip6 $result_file; then
				result +=1
				echo "double_innter_outer_tag(8100_over_88a8) $inner_tag over $outer_tag vf_outer_ip netperf failed"
			fi

			if ! do_vm_netperf $vm1 $server_inner_sametag_ip4 $server_inner_sametag_ip6 $result_file; then
				result +=1
				echo "double_outer_outer_tag(8100_over_88a8) $outer_tag over $outer_tag vf_inner_sametag_ip  netperf failed"
			fi
!
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ethtool -K \$NIC_TEST rxvlan off}
				{ethtool -K \$NIC_TEST txvlan off}
				{ethtool -K \$NIC_TEST tx-vlan-stag-hw-insert on}
				{ethtool -K \$NIC_TEST rx-vlan-stag-hw-parse on}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			if ! do_vm_netperf $vm1 $server_outer_ip4 $server_outer_ip6 $result_file;then
				result+=1
				echo "qinq_offload on single_outer_tag(88a8) $outer_tag vf_outer_ip netperf failed"
			fi

			local cmd=(
				{ping -c 10 $server_inner_ip4 }
				{ping -c 10 $server_inner_sametag_ip4}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				rlFail "fail:ping failed via offload on vf  qinq(8100_over_88a8)"
			fi

:<<!
			if ! do_vm_netperf $vm1 $server_inner_ip4 $server_inner_ip6 $result_file;then
				result += 1
				echo "qinq_offload on double_inner_outer_tag(8100_over_88a8) $inner_tag over $outer_tag vf_innter_ip netperf failed"
			fi

			if ! do_vm_netperf $vm1 $server_inner_sametag_ip4 $server_inner_sametag_ip6 $result_file; then
				result +=1
				echo "qinq_offload on double_outer_outer_tag(8100_over_88a8) $outer_tag over $outer_tag vf_inner_sametag_ip netperf failed"
			fi
!

			ip link set $nic_test vf 0 vlan 0

			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link delete \$NIC_TEST.$inner_tag}
				{ip link delete \$NIC_TEST.$outer_tag}
				{ip add flush \$NIC_TEST}
				{ethtool -K \$NIC_TEST rxvlan on}
				{ethtool -K \$NIC_TEST txvlan on}
				{ethtool -K \$NIC_TEST tx-vlan-stag-hw-insert off}
				{ethtool -K \$NIC_TEST rx-vlan-stag-hw-parse off}
				{ip link add link \$NIC_TEST name \$NIC_TEST.$outer_tag type vlan id $outer_tag protocol 802.1ad}
				{ip link add link \$NIC_TEST.$outer_tag name \$NIC_TEST.$outer_tag.$inner_tag type vlan id $inner_tag}
				{ip link add link \$NIC_TEST.$outer_tag name \$NIC_TEST.$outer_tag.$outer_tag type vlan id $outer_tag}
				{ip link set \$NIC_TEST.$outer_tag up}
				{ip link set \$NIC_TEST.$outer_tag.$inner_tag up}
				{ip link set \$NIC_TEST.$outer_tag.$outer_tag up}
				{ip addr add  $vf_outer_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr add  $vf_outer_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag}
				{ip addr add  $vf_inner_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag.$inner_tag}
				{ip addr add  $vf_inner_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag.$inner_tag}
				{ip addr add  $vf_inner_sametag_ip4/${ip4_mask_len} dev \$NIC_TEST.$outer_tag.$outer_tag}
				{ip addr add  $vf_inner_sametag_ip6/${ip6_mask_len} dev \$NIC_TEST.$outer_tag.$outer_tag}
				{ip addr show}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			echo "image_vm vlan 88a8=================================================================================================================================="
			if ! do_vm_netperf $vm1 $server_outer_ip4 $server_outer_ip6 $result_file;then
				result+=1
				echo "vm_qinq single_outer_tag(88a8) $outer_tag vf_outer_ip netperf failed"
			fi

			local cmd=(
				{ping -c 10 $server_inner_ip4 }
				{ping -c 10 $server_inner_sametag_ip4}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"
			if [ $? -ne 0 ];then
				rlFail "fail:ping failed via offload on vm  qinq(8100_over_88a8)"
			fi
:<<!
			if ! do_vm_netperf $vm1 $server_inner_ip4 $server_inner_ip6 $result_file;then
				result += 1
				echo "vm_qinq double_inner_outer_tag(8100_over_88a8) $inner_tag over $outer_tag vf_innter_ip netperf failed"
			fi

			if ! do_vm_netperf $vm1 $server_inner_sametag_ip4 $server_inner_sametag_ip6 $result_file; then
				result +=1
				echo "vm_qinq double_outer_outer_tag(8100_over_88a8) $outer_tag over $outer_tag vf_inner_sametag_ip netperf failed"
			fi
!
			local cmd=(
				{export NIC_TEST=\$\(ip link show \| grep $mac -B1 \| head -n1 \| awk \'\{print \$2\}\' \| sed \'s/://\'\)}
				{ip link delete \$NIC_TEST.$outer_tag.$inner_tag}
				{ip link delete \$NIC_TEST.$outer_tag.$outer_tag}
				{ip link delete \$NIC_TEST.$outer_tag}
			)
			vmsh cmd_set $vm1 "${cmd[*]}"

			sriov_detach_vf_from_vm $nic_test 0 1 $vm1

			if [ `echo $sw |grep 5200` ]; then
				# juniper 5200 update version. 88a8 and 8100 don't support at the same time. delete 88a8 config to let 8100 pass
				rlRun "swcfg del_interface_88a8 $sw $port"
			fi
		fi

			sriov_remove_vfs $nic_test 0
			sync_set server 8100_over_88a8_end
		else
			sync_wait server 8100_over_8100_start
			sync_set server 8100_over_8100_end
			sync_wait server 8100_over_88a8_start
			sync_set server 8100_over_88a8_end
		fi
	fi
	return $result
}

sriov_test_bug_reproducer_2103801(){
	# https://bugzilla.redhat.com/show_bug.cgi?id=2103801#c24
	if i_am_server; then
		sync_set client sriov_test_bug_reproducer_2103801_start 14400
		if [ $? -ne 0 ]; then
			rlFail "sync timeout with client side!!!" && { return 1; }
		else
			sync_wait client sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "sync timeout with client side!!!"; return 1 ; }
		fi
	else
		sync_wait server sriov_test_bug_reproducer_2103801_start 14400 || { rlFail "sync timeout with server side!!!"; return 1 ; }
		local NIC_NUM=1
		if [[ "${CLIENT_INTERFACES[*]}" != 'None' ]]; then
			local test_iface="$(get_test_nic ${NIC_NUM} ${CLIENT_INTERFACES[0]})"
		else
			local test_iface="$(get_test_nic ${NIC_NUM})"
		fi
		rlLog "got test nic is: ${test_iface}"
		local total_vfs=$(sriov_get_max_vf_from_pf ${test_iface})
		rlLog "got the total_vfs is: ${total_vfs}"
		local mac_perfix="$(get_mac_prefix $(hostname))01:" # MAC prefix used for VFs

		# find vf driver
		sriov_create_vfs ${test_iface} 0 1
		local check_vf_name=$(sriov_get_vf_iface ${test_iface} 0 1)
		local vf_driver_name=$(ethtool -i ${check_vf_name} | sed -n -e "/driver:/s/driver: //p")
		if [ -z ${vf_driver_name} ]; then
			rlFail "can't find vf driver"
			rlRun "sriov_remove_vfs ${nic_test} 0"
			sync_set server sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "sync timeout with server side!!!"; return 1 ; }
		fi
		rlLog "vf driver is: ${vf_driver_name}"
		sriov_remove_vfs ${test_iface}
		if [ ! -d /sys/bus/pci/drivers/${vf_driver_name} ]; then
			sync_set server sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "can't find vf driver in sys file"; return 1 ; }
		fi
		# start test
		dmesg -C
		sriov_create_vfs ${test_iface} 0 ${total_vfs}
		for i in $(seq 0 ${total_vfs}); do
			local mac_suffix=$(printf "%02x" ${i})
			ip link set ${test_iface} vf ${i} mac ${mac_perfix}${i} # Set VF mac address via PF
			local vf_bus_info=$(sriov_get_vf_bus_info ${test_iface} 0 ${i})
			echo "${vf_bus_info}" > /sys/bus/pci/drivers/${vf_driver_name}/unbind # unbind the VF from IAVF
		done
		sriov_remove_vfs ${test_iface}
		if [ $(dmesg | grep -c -i "Never saw reset") -ne 0 ]; then
			rlFail "got Never saw reset message on dmesg log"
		fi

		sync_set server sriov_test_bug_reproducer_2103801_end 14400 || { rlFail "sync timeout with server side!!!"; return 1 ; }
	fi
}

setup() {
	Configuring_NetworkManager_to_ignore_certain_devices
	if [[ $ENABLE_RT_KERNEL == "no" ]]; then
		rlRun install_pktgen
	elif [[ $ENABLE_RT_KERNEL == "yes" ]]; then
		sleep 1
	fi

	if [[ $ENABLE_RT_KERNEL == "no" ]]; then
		rlRun sriov_install
		rlRun sriov_cleanup
#		if (( "$rhel_version" >= "9" )); then
#			enable_libvirtd_as_default_rhel9
#		fi
	elif [[ $ENABLE_RT_KERNEL == "yes" ]]; then
		# stage 0 will install rt kernel, stage 2 will configure memory and cpu tuning, stage 3 will check configure and install.
		rlLog "REBOOTCOUNT is ${REBOOTCOUNT}"
		if [ x"${REBOOTCOUNT}" == x"0" ]; then
			rlRun set_preinstall_host
#			if (( "$rhel_version" >= "9" )); then
#				enable_libvirtd_as_default_rhel9
#			fi
			# install rt-test tuned libvirt, configure hugepage and cpu isolation
			rlLog "###############install rt-test tuned libvirt, configure hugepage and cpu isolation, will reboot system##############"
			/usr/bin/python3 ${CASE_PATH}/rt-kernel/rt_kernel_paramter.py --os_type="host" --stage="0" || exit 1
		elif [ x"${REBOOTCOUNT}" == x"1" ]; then
			rlLog "REBOOTCOUNT is ${REBOOTCOUNT}"
			rlRun install_pktgen
			/usr/bin/python3 ${CASE_PATH}/rt-kernel/rt_kernel_paramter.py --os_type="host" --stage="1" || exit 1
			rlLog  "###############Host has been setup rt kernel successfully.###############"
		fi
		netperf_install
		rlLog "###############Netperf install succeed ##############"
		#enable netserver
		pkill netserver; sleep 2; netserver
		chmod 666 /dev/kvm
		sriov_cleanup
	fi

	if [ ! -e /usr/bin/python ];then
		if [ -e "/usr/libexec/platform-python3.6" ];then
				ln -s /usr/libexec/platform-python3.6 /usr/bin/python
		elif [ -e "/usr/bin/python2" ];then
			ln -s /usr/bin/python2 /usr/bin/python
		fi
	fi

	if [[ $ENABLE_RT_KERNEL == "no" ]]; then
		if i_am_client; then
			echo "SRIOV_TEST_RESULT($nic_driver/$nic_test):	$(date)" > $result_file
			echo "kernel: $(uname -r)" >> $result_file
			echo "CLIENTS: $CLIENTS" >> $result_file
			echo "SERVERS: $SERVERS" >> $result_file
			echo ""
		fi
		rlRun "sriov_setup"
		if (($rhel_version == 7)); then
			if [ -z "$REBOOTCOUNT" ] || [ "$REBOOTCOUNT" -eq 0 ]; then
				rhts-reboot
				rlRun "sriov_setup"
			fi
		fi
	elif [[ $ENABLE_RT_KERNEL == "yes" ]]; then
		if i_am_client; then
			echo "SRIOV_TEST_RESULT($nic_driver/$nic_test):	$(date)" > $result_file
			echo "kernel: $(uname -r)" >> $result_file
			echo "CLIENTS: $CLIENTS" >> $result_file
			echo "SERVERS: $SERVERS" >> $result_file
			echo ""
		fi
		rlRun "define_config_vm"
	fi
}

preconfiguration() {

	#if [[ $ENABLE_RT_KERNEL == "no" ]]; then
	#  rm -f /usr/local/bin/vmsh
	#  cp ./vmsh /usr/local/bin
	#fi

	#HOST_IP=$(cat /usr/share/libvirt/networks/default.xml|grep "ip address"|awk -F" " '{print $2}'|awk -F"\"" '{print $2}')
	#GUEST_IP=$(cat /usr/share/libvirt/networks/default.xml|grep "range start="|awk -F" " '{print $2}'|awk -F"\"" '{print $2}')
	#vmsh change_local_passwd redhat

	rlRun "ip link show | grep virbr1 || ip link add name virbr1 type bridge"
	rlRun "ip link set virbr1 up"
	ip link show virbr0
	if [ $? -ne 0 ]; then
		rlRun "virsh net-list --all"
		rlRun "virsh net-start default" || rlRun "virsh net-destroy default"
		rlRun "virsh net-autostart default" && rlRun "virsh net-start default"
		if (( $rhel_version < 9 )); then
			rlRun "systemctl restart libvirtd"
		else
			rlRun "systemctl restart virtnetworkd.service"
		fi
		rlRun "virsh net-list --all"
		sleep 10
		rlRun "ip link show virbr0" && rlFail "virbr0 can't start as well"
		rlRun "systemctl status virtqemud --no-pager -l"
	fi
	local r_version=$( cat /etc/redhat-release | sed  's/\(.*\)\([0-9].[0-9]\)\(.*\)/\2/g')
#	if [[ $(echo "${r_version} <= 8.6" | bc) -eq 1 ]]; then
#		rlRun "systemctl restart libvirtd"
#	fi

	# make sure netserver start for each test task started
	rlRun "pkill -9 netserver; sleep 2 ; netserver"
	vmsh run_cmd $vm1 "pkill netserver ; sleep 2 ; netserver"
	vmsh run_cmd $vm2 "pkill netserver ; sleep 2 ; netserver"


	#restart vm if needed
	virsh list --all | grep $vm1 | grep running || virsh start $vm1
	virsh list --all | grep $vm2 | grep running || virsh start $vm2

	if (($rhel_version >= 7)); then
		vmsh run_cmd $vm1 "systemctl stop NetworkManager"
		vmsh run_cmd $vm2 "systemctl stop NetworkManager"
	fi

}

disable_guest() {
	virsh list --all | grep $vm1 | grep running && virsh shutdown $vm1
	virsh list --all | grep $vm2 | grep running && virsh shutdown $vm2

}

Configuring_NetworkManager_to_ignore_certain_devices()
{
	nic_bkr=$(get_default_iface)
	echo DEBUG::: beaker_nic=${nic_bkr}
	rhel_verx=$(rpm -E %rhel)
	if [ $rhel_verx -ge 7 ]; then
		if [[ x"${nic_bkr}" == x"" ]]; then
			echo "can't found beaker port"
		else
			if [ -e /etc/NetworkManager/conf.d/99-unmanaged-devices.conf ]; then
				rm -rf /etc/NetworkManager/conf.d/99-unmanaged-devices.conf
			fi
			cat <<-EOF > /etc/NetworkManager/conf.d/99-unmanaged-devices.conf
			[keyfile]
			unmanaged-devices=*,except:interface-name:${nic_bkr},except:type:loopback,except:type:bridge
			EOF
		fi
		systemctl reload NetworkManager
	else
		echo "doesn't support NM to control network"
	fi
}
#######################
# main

rlJournalStart

rlPhaseStart WARN determin_interface_and_setup
rlRun sriov_get_ipaddr

if [ "${SRIOV_ENABLE_SELINUX}" = "yes" ];then
		setenforce 1
else
		setenforce 0
fi


if i_am_client; then
	if [[ "${CLIENT_INTERFACES}" == 'None' ]]; then
		rlRun "nic_test='$(get_required_iface)'"
		rlLog "nic_test=$nic_test"
		rlRun "ethtool -i $nic_test"
		rlRun "nic_driver='$(ethtool -i $nic_test | grep driver | awk '{print $2}')'"
	else
		CLIENT_INTERFACES=($CLIENT_INTERFACES)
		nic_test=${CLIENT_INTERFACES[0]}
		if [[ -z "${nic_test[*]}" ]]; then
			rlFail "FATAL ERROR: pci_list or nic_list is not availabe!"
			exit 1
		fi
	fi
else
	if [[ "${SERVER_INTERFACES}" == 'None' ]]; then
		rlRun "nic_test='$(get_required_iface)'"
		rlLog "nic_test=$nic_test"
		rlRun "ethtool -i $nic_test"
		rlRun "nic_driver='$(ethtool -i $nic_test | grep driver | awk '{print $2}')'"
	else
		SERVER_INTERFACES=($SERVER_INTERFACES)
		nic_test=${SERVER_INTERFACES[0]}
		if [[ -z "${nic_test[*]}" ]]; then
			rlFail "FATAL ERROR: pci_list or nic_list is not availabe!"
			exit 1
		fi
	fi
fi

if i_am_client; then
	mac4vm1="00:de:ad:$(printf "%02x" $ipaddr):00:01"
	rlLog "mac4vm1 is: ${mac4vm1}"
	mac4vm2="00:de:ad:$(printf "%02x" $ipaddr):00:02"
	rlLog "mac4vm2 is: ${mac4vm2}"
	mac4vm1if2="00:de:ad:$(printf "%02x" $ipaddr):00:03"
	rlLog "mac4vm1if2 is: ${mac4vm1if2}"
else
	mac4vm1="00:de:ad:$(printf "%02x" $ipaddr):00:21"
	rlLog "mac4vm1 is: ${mac4vm1}"
	mac4vm2="00:de:ad:$(printf "%02x" $ipaddr):00:22"
	rlLog "mac4vm2 is: ${mac4vm2}"
	mac4vm1if2="00:de:ad:$(printf "%02x" $ipaddr):00:23"
	rlLog "mac4vm1if2 is: ${mac4vm1if2}"
fi

result_file=${result_file:-"sriov_$nic_driver.log"}
# disable DHCP and NetworkManager on the interface
if [  x"$SRIOV_TOPO"  == x"sriov_test_vmvf_connectivity_remain" ]
then
	cat /etc/sysconfig/network-scripts/ifcfg-${nic_test} | \
		sed 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' | \
		tee  /etc/sysconfig/network-scripts/ifcfg-${nic_test}
else
	cat /etc/sysconfig/network-scripts/ifcfg-${nic_test} | \
		sed 's/BOOTPROTO=dhcp/BOOTPROTO=none/g' | \
		sed 's/NM_CONTROLLED=yes/NM_CONTROLLED=no/g' | \
		tee  /etc/sysconfig/network-scripts/ifcfg-${nic_test}
fi

ip link set $nic_test up
ip link show dev $nic_test

rlPhaseEnd

if [ "$SRIOV_SKIP_SETUP_ENV" != "yes" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|setup\b)"; then
	rlPhaseStartTest "setup_test_configuration"
	rlRun "setup"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_pf_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_pf_remote"
	rlRun "sriov_test_pf_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_pf_remote_jumbo\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_pf_remote_jumbo"
	rlRun "sriov_test_pf_remote_jumbo"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_pf_vlan_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_pf_vlan_remote"
	rlRun "sriov_test_pf_vlan_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_remote"
	rlRun "sriov_test_vf_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_remote_switchdev\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_remote_switchdev"
	rlRun "sriov_test_vf_remote_switchdev"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_remote_jumbo\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_remote_jumbo"
	rlRun "sriov_test_vf_remote_jumbo"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_vlan_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_vlan_remote"
	rlRun "sriov_test_vf_vlan_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_remote"
	rlRun "sriov_test_vmvf_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_1733181_vmvf_remote_pfdown\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_1733181_vmvf_remote_pfdown"
	rlRun "sriov_test_1733181_vmvf_remote_pfdown"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_remote_jumbo\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_remote_jumbo"
	rlRun "sriov_test_vmvf_remote_jumbo"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_vlan_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_vlan_remote"
	rlRun "sriov_test_vmvf_vlan_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_vlan_remote_jumbo\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_vlan_remote_jumbo"
	rlRun "sriov_test_vmvf_vlan_remote_jumbo"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_vlan_remote_1\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_vlan_remote_1"
	rlRun "sriov_test_vmvf_vlan_remote_1"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_pf_vmvf\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_pf_vmvf"
	rlRun "sriov_test_pf_vmvf"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_pf_vmvf_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_pf_vmvf_vlan"
	rlRun "sriov_test_pf_vmvf_vlan"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_vmvf\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_vmvf"
	rlRun "sriov_test_vmvf_vmvf"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_vmvf_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_vmvf_vlan"
	rlRun "sriov_test_vmvf_vmvf_vlan"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_bond_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_bond_remote"
	rlRun "sriov_test_vmvf_bond_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf1_vmvf2_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf1_vmvf2_remote"
	rlRun "sriov_test_vmvf1_vmvf2_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf1_vmvf2_vlan_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf1_vmvf2_vlan_remote"
	rlRun "sriov_test_vmvf1_vmvf2_vlan_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1212361\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1212361"
	rlRun "sriov_test_bz1212361"
	rlPhaseEnd
fi

#same case as sriov_test_vmvf_remote_jumbo
#if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1145063\b)"; then
#	rlPhaseStartTest "sriov_test_bz1145063"
#	if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
#	rlRun "clear_dmesg_message"
#  fi
#	rlRun "sriov_test_bz1145063"
#	rlPhaseEnd
#fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1205903\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1205903"
	rlRun "sriov_test_bz1205903"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_trusted_vf_override_macaddr_via_bonding\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_trusted_vf_override_macaddr_via_bonding"
	rlRun "sriov_test_trusted_vf_override_macaddr_via_bonding"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac0\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac0"
	rlRun "sriov_test_bond_failovermac0"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac1\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac1"
	rlRun "sriov_test_bond_failovermac1"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac2\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac2"
	rlRun "sriov_test_bond_failovermac2"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac0_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac0_vlan"
	rlRun "sriov_test_bond_failovermac0_vlan"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac1_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac1_vlan"
	rlRun "sriov_test_bond_failovermac1_vlan"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac2_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac2_vlan"
	rlRun "sriov_test_bond_failovermac2_vlan"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac1_pf_down\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac1_pf_down"
	rlRun "sriov_test_bond_failovermac1_pf_down"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_failovermac2_swport_down\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_failovermac2_swport_down"
	rlRun "sriov_test_bond_failovermac2_swport_down"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_test_bz1701191\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1701191"
	rlRun "sriov_test_bz1701191"
	rlPhaseEnd
fi


if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1392128\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1392128"
	rlRun "sriov_test_bz1392128"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_trusted_vf_allmulticast\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_trusted_vf_allmulticast"
	rlRun "sriov_test_trusted_vf_allmulticast"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_trust_broadcast\b)"; then
	rlPhaseStartSetup "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_trust_broadcast"
	rlRun "sriov_test_vf_trust_broadcast"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_max_vfs\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_max_vfs"
	rlRun "sriov_test_max_vfs"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_vlan_offload_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_vlan_offload_remote"
	rlRun "sriov_test_vmvf_vlan_offload_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_trusted_vf_ipv6addr\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_trusted_vf_ipv6addr"
	rlRun "sriov_test_trusted_vf_ipv6addr"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_max_vfs_attaching_to_different_vms\b)"; then
	rlPhaseStartTest "sriov_test_max_vfs_attaching_to_different_vms"
	rlRun "disable_guest"
	rlRun "sriov_test_max_vfs_attaching_to_different_vms"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_different_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_different_vlan"
	rlRun "sriov_test_vmvf_different_vlan"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1441909\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1441909"
	rlRun "sriov_test_bz1441909"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_lacp\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_lacp"
	rlRun "sriov_test_bond_lacp"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_trusted_vf_promisc\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_trusted_vf_promisc"
	rlRun "sriov_test_trusted_vf_promisc"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1445814\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1445814"
	rlRun "sriov_test_bz1445814"
	rlPhaseEnd
fi

if [ "$SRIOV_RUN_BY_PARTNER" = "no" ];then
	if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vfname\b)"; then
		rlPhaseStartTest "preconfiguration"
		rlRun preconfiguration
		rlPhaseEnd
		rlPhaseStartTest "sriov_test_vfname"
		rlRun "sriov_test_vfname"
		rlPhaseEnd
	fi
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_hostdev_vmvf_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_hostdev_vmvf_remote"
	rlRun "sriov_test_hostdev_vmvf_remote"
	rlPhaseEnd
fi

#if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1489964\b)"; then
#	rlPhaseStartTest "sriov_test_bz1489964"
#	if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
#	rlRun "clear_dmesg_message"
#  fi
#	rlRun "sriov_test_bz1489964"
#	rlPhaseEnd
#fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf1vf2_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf1vf2_remote"
	rlRun "sriov_test_vmvf1vf2_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf1vf2_same_pf_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf1vf2_same_pf_remote"
	rlRun "sriov_test_vmvf1vf2_same_pf_remote"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_spoofchk\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_spoofchk"
	rlRun "sriov_test_spoofchk"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1493953\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1493953"
	rlRun "sriov_test_bz1493953"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1483396\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1483396"
	rlRun "sriov_test_bz1483396"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz1794812_excessive_interrupts\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz1794812_excessive_interrupts"
	rlRun "sriov_test_bz1794812_excessive_interrupts"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_multicast\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_multicast"
	rlRun "sriov_test_vmvf_multicast"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmpf_vmvf_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmpf_vmvf_remote"
	rlRun "sriov_test_vmpf_vmvf_remote"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmpfbond_vmvfbond_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmpfbond_vmvfbond_remote"
	rlRun "sriov_test_vmpfbond_vmvfbond_remote"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_attach_method_is_forward_hostdev\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_attach_method_is_forward_hostdev"
	rlRun "sriov_test_attach_method_is_forward_hostdev"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_attach_method_is_forward_hostdev_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_attach_method_is_forward_hostdev_vlan"
	rlRun "sriov_test_attach_method_is_forward_hostdev_vlan"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_max_tx_rate\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_max_tx_rate"
	rlRun "sriov_test_vmvf_max_tx_rate"
	rlPhaseEnd
fi
#if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmpf_remote\b)"; then
#	rlPhaseStartTest "sriov_test_vmpf_remote"
#	if [[ $ENABLE_RT_KERNEL == "yes" ]]; then
#	rlRun "clear_dmesg_message"
#  fi
#	rlRun "sriov_test_vmpf_remote"
#	rlPhaseEnd
#fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_create_remove_vfs_memoryleak\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_create_remove_vfs_memoryleak"
	rlRun "sriov_test_create_remove_vfs_memoryleak"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_reg_ureg_multicast_addr\b)"; then
	rlPhaseStartSetup "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_reg_ureg_multicast_addr"
	rlRun "sriov_test_vmvf_reg_ureg_multicast_addr"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_creation\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_creation"
	rlRun "sriov_test_vf_creation"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_vlan_negative\b)"; then
	rlPhaseStartSetup "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_vlan_negative"
	rlRun "sriov_test_vf_vlan_negative"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_pf_speed_consistency\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_pf_speed_consistency"
	rlRun "sriov_test_vf_pf_speed_consistency"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_remote_switchdev\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_remote_switchdev"
	rlRun "sriov_test_vmvf_remote_switchdev"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_mac_switchdev_bz1814350\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_mac_switchdev_bz1814350"
	rlRun "sriov_test_vf_mac_switchdev_bz1814350"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_switchdev_bz1870593\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_switchdev_bz1870593"
	rlRun "sriov_test_switchdev_bz1870593"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_remote_jumbo_switchdev\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_remote_jumbo_switchdev"
	rlRun "sriov_test_vf_remote_jumbo_switchdev"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_remote_jumbo_switchdev\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_remote_jumbo_switchdev"
	rlRun "sriov_test_vmvf_remote_jumbo_switchdev"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_cntvf_cntvf\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_cntvf_cntvf"
	rlRun "sriov_test_cntvf_cntvf"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_cntvf_cntvf_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_cntvf_cntvf_vlan"
	rlRun "sriov_test_cntvf_cntvf_vlan"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_cntvf_cntvf_jumbo\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_cntvf_cntvf_jumbo"
	rlRun "sriov_test_cntvf_cntvf_jumbo"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_podcntvf_podcntvf\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_podcntvf_podcntvf"
	rlRun "sriov_test_podcntvf_podcntvf"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_podcntvf1_podcntvf2\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_podcntvf1_podcntvf2"
	rlRun "sriov_test_podcntvf1_podcntvf2"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_podcntvf_remote\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_podcntvf_remote"
	rlRun "sriov_test_podcntvf_remote"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_podcnts_vfs_remote_bz2088787\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_podcnts_vfs_remote_bz2088787"
	rlRun "sriov_test_podcnts_vfs_remote_bz2088787"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_cntvf_reboot\b)"; then
		rlPhaseStartTest "sriov_test_cntvf_reboot"
		rlRun "sriov_test_cntvf_reboot"
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_connectivity_remain\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_connectivity_remain"
	rlRun "sriov_test_vmvf_connectivity_remain"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_not_created_bz1875338\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vf_not_created_bz1875338"
	rlRun "sriov_test_vf_not_created_bz1875338"
	rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_iface_not_created\b)"; then
	rlPhaseStartTest "sriov_test_vf_iface_not_created"
	rlRun "sriov_test_vf_iface_not_created"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_hibernation\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_vmvf_hibernation"
	rlRun "sriov_test_vmvf_hibernation"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_pf_steering_switchdev_bz1856660\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_pf_steering_switchdev_bz1856660"
	rlRun "sriov_test_pf_steering_switchdev_bz1856660"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_delete_vm_with_kernel_args\b)"; then
	rlPhaseStartTest "sriov_test_delete_vm_with_kernel_args"
	rlRun "sriov_test_delete_vm_with_kernel_args"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_negative_create_vfs_2000180\b)"; then
	rlPhaseStartTest "sriov_test_negative_create_vfs_2000180"
	rlRun "sriov_test_negative_create_vfs_2000180"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_reproduce_2021326\b)"; then
	rlPhaseStartTest "sriov_test_reproduce_2021326"
	rlRun "sriov_test_reproduce_2021326"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_reproduce_2021326_reboot_check\b)"; then
	rlPhaseStartTest "sriov_test_reproduce_2021326_reboot_check"
	rlRun "sriov_test_reproduce_2021326_reboot_check"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vf_cfg_stress\b)"; then
	rlPhaseStartTest "sriov_test_vf_cfg_stress"
	rlRun "sriov_test_vf_cfg_stress"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_mode2\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_mode2"
	sriov_test_bond_mode2
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bond_mode2_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bond_mode2_vlan"
	sriov_test_bond_mode2_vlan
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_2049237_VF_mac_reset_zero\b)"; then
		rlPhaseStartTest "sriov_test_2049237_VF_mac_reset_zero"
		sriov_test_2049237_VF_mac_reset_zero
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_2049237_VF_mac_reset_zero_reboot_check\b)"; then
		rlPhaseStartTest "sriov_test_2049237_VF_mac_reset_zero_reboot_check"
		sriov_test_2049237_VF_mac_reset_zero_reboot_check
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz2057244_vf_not_up\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_bz2057244_vf_not_up"
	rlRun "sriov_test_bz2057244_vf_not_up"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz2070917_vlan_bridge_nic\b)"; then
	rlPhaseStartTest "sriov_test_bz2070917_vlan_bridge_nic"
	rlRun "sriov_test_bz2070917_vlan_bridge_nic"
	rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz2055446_no_arp_reply\b)"; then
		rlPhaseStartTest "sriov_test_bz2055446_no_arp_reply"
		rlRun "sriov_test_bz2055446_no_arp_reply"
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz2071027_double_tagging\b)"; then
		rlPhaseStartTest "sriov_test_bz2071027_double_tagging"
		rlRun "sriov_test_bz2071027_double_tagging"
		rlPhaseEnd
fi

#if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_vmvf_testpmd_macswap\b)"; then
#	rlPhaseStartTest "sriov_test_vmvf_testpmd_macswap"
#	rlRun "sriov_test_vmvf_testpmd_macswap"
#	rlPhaseEnd
#fi
#if [ "$SRIOV_SKIP_SETUP_ENV" != "yes" ]; then
#	   sriov_cleanup
#fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_bz2008373\b)"; then
		rlPhaseStartTest "sriov_test_bz2008373"
		rlRun "sriov_test_bz2008373"
		rlRun -l "dmesg | grep -c -i 'Invalid message from VF'" 1
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|vf_intf_garp_check\b)"; then
		rlPhaseStartTest "vf_intf_garp_check"
		rlRun "vf_intf_garp_check"
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_link_down_on_close\b)"; then
		rlPhaseStartTest "sriov_test_link_down_on_close"
		rlRun "sriov_test_link_down_on_close"
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_reproduce_2000180\b)"; then
		rlPhaseStartTest "sriov_test_reproduce_2000180"
		rlRun "sriov_test_reproduce_2000180"
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_test_vlan_qinq_baisc\b)"; then
		rlPhaseStartTest "preconfiguration"
		rlRun preconfiguration
		rlPhaseEnd
	rlPhaseStartTest "sriov_test_vlan_qinq_baisc"
		rlRun "sriov_test_vlan_qinq_baisc"
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_test_bz2080033_re_assign_MACs_to_VFs\b)"; then
	rlPhaseStartTest "sriov_test_bz2080033_re_assign_MACs_to_VFs"
		rlRun "sriov_test_bz2080033_re_assign_MACs_to_VFs"
		rlPhaseEnd
fi

if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_test_bug_reproducer_2103801\b)"; then
	rlPhaseStartTest "sriov_test_bug_reproducer_2103801"
		rlRun "sriov_test_bug_reproducer_2103801"
		rlPhaseEnd
fi
if [ -z "$SRIOV_TOPO" ] || echo $SRIOV_TOPO | grep -q -E "(sriov_all|sriov_test_spoofchk_vlan\b)"; then
	rlPhaseStartTest "preconfiguration"
	rlRun preconfiguration
	rlPhaseEnd
	rlPhaseStartTest "sriov_test_spoofchk_vlan"
	rlRun "sriov_test_spoofchk_vlan"
	rlPhaseEnd
fi

rlJournalPrintText
rlJournalEnd
