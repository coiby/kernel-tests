#! /bin/bash
# shellcheck disable=SC1083,SC2128,SC2154
source /etc/profile
source /root/.bash_profile

# Include Beaker environment
#CASE_PATH=${CASE_PATH:-"/mnt/tests/kernel/networking/vnic/sriov"}

set_preinstall_host()
{
	local CASE_PATH=$(dirname $(readlink -f $BASH_SOURCE))
	source ${CASE_PATH}/../../../common/include.sh
	rlLog "run set_preinstall_host"
	yum install -y pciutils vim
	yum install -y podman
	yum install -y python3 python3-pip
	yum install -y wget
	yum install -y expect
	yum install -y kernel-rt-kvm kernel-rt-modules-extra kernel-rt-selftests-internal
	# spicfy xmltodict-0.12.0-py2.py3-none-any file url
	pip3 install ${CASE_PATH}/xmltodict-0.12.0-py2.py3-none-any.whl
	netperf_install
	scapy_install
}

define_config_vm()
{
	local CASE_PATH=$(dirname $(readlink -f $BASH_SOURCE))
	rm -f /usr/local/bin/vmsh
	cp ${CASE_PATH}/../../../common/tools/vmsh /usr/local/bin/
	yum -y install virt-install

	# stop security features
	rhel_version=$(cut -f1 -d. /etc/redhat-release | sed 's/[^0-9]//g')
	if (($rhel_version >= 7)); then
#	systemctl stop NetworkManager
	systemctl stop firewalld
	fi
	iptables -F
	ip6tables -F
	systemctl stop firewalld

	#brctl show
	ip link show type bridge
	ip addr list
	virsh net-define /usr/share/libvirt/networks/default.xml
	virsh net-start default
	virsh net-autostart default

	# nmcli connection add ifname virbr1 connection.type bridge con-name virbr1
	# nmcli connection up virbr1

	ip link show | grep virbr1 || ip link add name virbr1 type bridge
	ip link set virbr1 up
	ip link show | grep virbr0 || virsh net-info default
	ip link set virbr0 up
	# install vm and configure kernel-rt in vm
	# use a repo to install kernel
	# /usr/bin/python3 ./rt-kernel/rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:01:01:01" --mac4vm1if2="00:de:ad:01:01:02" --mac4vm2="00:de:ad:02:02:02" --vm_cpunum="5" --rhel_image_name="rhel8.6-4.18.0-369.rt7.154.el8.qcow2" --enable_default_yum="yes" --vm_kernel_name="None" --enable_vm_xml_tuning="yes" --kernel_repo="None" --brew_task_id="None" --test_nic=ens5f0
	# /usr/bin/python3 ./rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:01:01:01" --mac4vm1if2="00:de:ad:01:01:02" --mac4vm2="00:de:ad:02:02:02" --vm_cpunum="5" --rhel_image_name="rhel8.6-4.18.0-369.rt7.154.el8.qcow2" --enable_default_yum="no" --vm_kernel_name="kernel-rt-4.18.0-371.rt7.156.el8.2021326.cc6236f9" --enable_vm_xml_tuning="yes" --kernel_repo="http://brew-task-repos.usersys.redhat.com/repos/scratch/jkc/kernel-rt/4.18.0/371.rt7.156.el8.2021326.cc6236f9/x86_64)" --brew_task_id="None" --test_nic=ens5f0
	# use brew package to install kernel
	# /usr/bin/python3 ./rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:01:01:01" --mac4vm1if2="00:de:ad:01:01:02" --mac4vm2="00:de:ad:02:02:02" --vm_cpunum="5" --rhel_image_name="rhel8.6-4.18.0-369.rt7.154.el8.qcow2" --enable_default_yum="no" --vm_kernel_name="kernel-rt-4.18.0-369.rt7.154.el8" --enable_vm_xml_tuning="yes" --kernel_repo="None" --brew_task_id="None" --test_nic=ens5f0
	# use brew task id to install kernel
	# /usr/bin/python3 ./rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:01:01:01" --mac4vm1if2="00:de:ad:01:01:02" --mac4vm2="00:de:ad:02:02:02" --vm_cpunum="5" --rhel_image_name="rhel8.6-4.18.0-369.rt7.154.el8.qcow2" --enable_default_yum="no" --vm_kernel_name="None" --enable_vm_xml_tuning="yes" --kernel_repo="None" --brew_task_id="43154296" --test_nic=ens5f0

	/usr/bin/python3 ${CASE_PATH}/rt_kernel_paramter.py --os_type="vm" --vm_names="$vm1,$vm2" --mac4vm1="$mac4vm1" --mac4vm1if2="$mac4vm1if2" --mac4vm2="$mac4vm2" --vm_cpunum="$VM_CPUNUM" --rhel_image_name="${image_name}" --enable_default_yum="$ENABLE_DEFAULT_YUM" --vm_kernel_name="$VM_KERNEL_NAME" --enable_vm_xml_tuning="$ENABLE_VM_XML_TUNING" --kernel_repo="$GUEST_KERENL_REPO" --brew_task_id="$BREW_TASK_ID" --test_nic=${nic_test} || exit 1
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
		{source /mnt/tests/kernel/networking/common/install.sh}
		{netperf_install}
		{pkill netserver\; sleep 2\; netserver}
		# work around bz883695
		{lsmod \| grep mlx4_en \|\| modprobe mlx4_en}
		{tshark -v \&\>/dev/null \|\| yum -y install wireshark}
		)
	/usr/local/bin/vmsh cmd_set $vm1 "${cmd[*]}"
	/usr/local/bin/vmsh cmd_set $vm2 "${cmd[*]}"

	if [ -n "$VM_RUN_CMD" ];then
		/usr/local/bin/vmsh run_cmd $vm1 "$VM_RUN_CMD"
		/usr/local/bin/vmsh run_cmd $vm2 "$VM_RUN_CMD"
	fi
	virsh autostart $vm1
	virsh autostart $vm2
	swapoff -a
}
