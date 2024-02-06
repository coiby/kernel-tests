#! /bin/bash
# shellcheck disable=SC2154
source /etc/profile
source /root/.bash_profile
CASE_PATH=${CASE_PATH:-"/mnt/tests/kernel/networking/vnic/sriov"}
source /mnt/tests/kernel/networking/common/include.sh
source ${CASE_PATH}/sriov/env.sh

set_preinstall_host()
{
	yum install -y podman
	yum install -y python38
	yum install -y wget
	yum install -y expect
	# spicfy xmltodict-0.12.0-py2.py3-none-any file url
	pip-3 install ${CASE_PATH}/rt-kernel/xmltodict-0.12.0-py2.py3-none-any.whl
	bash brewkoji_install.sh
}

set_preinstall_vm()
{
	virsh net-define /usr/share/libvirt/networks/default.xml
	virsh net-start default
	virsh net-autostart default

	/usr/sbin/ip link show | grep virbr1 || /usr/sbin/ip link add name virbr1 type bridge
	/usr/sbin/ip link set virbr1 up
}

MARKER=/tmp/RT_STAGE
if [ ! -f "$MARKER" ]; then
	echo 0 > $MARKER
fi

stage=$(cat $MARKER)
while [[ "$stage" != "fin" ]] ; do
	echo "Executing stage=$stage"
	case "$stage" in
			0)
	echo 1 > $MARKER
	crontab -l | grep "@reboot sh ${CASE_PATH}/rt-kernel/manual_run_set_up.sh"
	if [ ! $?  ] || [ ! `crontab -l` ] ;then
		   echo "@reboot sh ${CASE_PATH}/rt-kernel/manual_run_set_up.sh"  >> /var/spool/cron/root
	fi

	#configure rt-kernel yum from repo.json
	#install kernel-rt/rt-tests/tuned/qemu-kvm-rhev/libvirt/ from repo
	set_preinstall_host
	/usr/bin/python3 ${CASE_PATH}/rt-kernel/rt_kernel_paramter.py --os_type="host" --stage="0" --enable_default_yum=$ENABLE_DEFAULT_YUM || exit 1
	;;
		1)
			echo 2 > $MARKER
			# isolate cores and set hugepage to kernel line
			# set hugepage pages in sysctl.conf
			/usr/bin/python3 ${CASE_PATH}/rt-kernel/rt_kernel_paramter.py --os_type="host" --stage="1" || exit 1
			;;
		2)
			echo fin > $MARKER
			# reserve hugepage
			/usr/bin/python3 ${CASE_PATH}/rt-kernel/rt_kernel_paramter.py --os_type="host" --stage="2" || exit 1
			echo  "set_up.sh: Host has been setup successfully."
			# install vm and configure kernel-rt in vm
			set_preinstall_vm
			python3 ${CASE_PATH}/rt-kernel/rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:$(printf "%02x" $ipaddr):00:21" --mac4vm1if2="00:de:ad:$(printf "%02x" $ipaddr):00:22" --mac4vm2="00:de:ad:$(printf "%02x" $ipaddr):00:23" --vm_cpunum=5 --vm_rhel_version="8.4" --enable_default_yum="yes" || exit 1
			break
			;;
		esac
done

crontab -r
rm -rf $MARKER
