part1:
1.check yum repo(if need to install newest repo, please check https://brewweb.engineering.redhat.com/brew/buildinfo?buildID=1298380)
2.configure yum repo(cat "" > /etc/yum.repo.d/name.repo)
3.install kernel-rt,kernel-kvm(need to install packages like: moudles-internal,kernel-rt-core....)
4.check successfully install kernel-rt and correspending package
5.install tuned tools(contain tuna, tuned, tuned-profiled-nfv)
6.check successfully install tuned tools
7.install rt-test and cyclictest tool
8.check successfully install rt-test and cyclictes

part2：
1.configure hugepage 1G ( grubby --args="default_hugepagesz=1G" --update-kernel=`grubby --default-kernel`)
2.set cpu isolate
- check cpu arc(cores)
- keep at least two cores role as housekeeping(can be parameters)
# echo isolated_cores=1,3,5,7,9,11,13,15,17,19,12,14,16,18 >> /etc/tuned/realtime-virtual-host-variables.conf
- configure tuned profile file
# echo isolate_managed_irq=Y >> /etc/tuned/realtime-virtual-host-variables.conf
- load profile
# tuned-adm profile realtime-virtual-host
3.reboot system
4.check system online
5.check configuration apply in system
-------------------------------------------------------------------------------------------------------
in step 2
For RHEL8.2 version
- add "mitigations=off" to kernel line.
# grubby --args="mitigations=off" --update-kernel=`grubby --default-kernel`

- verify that the configuration changes have been applied after reboot: "mitigations=off" should be in kernel line.
# cat /proc/cmdline
BOOT_IMAGE=(hd0,msdos1)/vmlinuz-4.18.0-192.rt13.50.el8.x86_64 ... tsc=nowatchdog mitigations=off

FOR RHEL7
- add "spectre_v2=off nopti" to kernel line.
# grubby --args="spectre_v2=off nopti " --update-kernel=`grubby --default-kernel`

- disable kvm-intel.vmentry_l1d_flush
# grubby --args="kvm-intel.vmentry_l1d_flush=never" --update-kernel=`grubby --default-kernel`

- verify that the configuration changes have been applied after reboot: "spectre_v2=off nopti",
"kvm-intel.vmentry_l1d_flush=never" should be in kernel line.
# cat /proc/cmdline
BOOT_IMAGE=/vmlinuz-3.10.0-1062.18.1.rt56.1046.el7.x86_64 ... spectre_v2=off nopti kvm-intel.vmentry_l1d_flush=never

part3:
1. follow kernel team vm file to create vm(one or multipule )
rhel7.6.z.xml
rhel7.7.z.xml
rhel7.8.z.xml
rhel8.2.repo.xml

part1 and part2 can be use in host and vm

1.set_up.sh main need to coding a function
2.runtest.sh add set_up function
3.ENABLE_RT_KERNEL to adjust enable RT install procress or nomarl procress.
4.delete sriov_config_rt_kernel_vm_repo() ,install_rt_kernel() in runtest.sh and restore sriov_setup
5.add in set_up.sh
	local cmd=(
		{iptables -F}
		{ip6tables -F}
		{systemctl stop firewalld}
		{setenforce 0}
		{yum install -y wget}
		{yum install -y tcpdump}
		{yum install -y bzip2}
		{yum install -y gcc}
		{source /mnt/tests/kernel/networking/common/install.sh}
		{netperf_install}
		{pkill netserver\; sleep 2\; netserver}
		# work around bz883695
		{lsmod \| grep mlx4_en \|\| modprobe mlx4_en}
		{tshark -v \&\>/dev/null \|\| yum -y install wireshark}
	)
	vmsh cmd_set $vm1 "${cmd[*]}"
	vmsh cmd_set $vm2 "${cmd[*]}"
	
6.install pktgen add in set_up.sh, install_pktgen define in runtest.sh
7.reboot issue(choose virsh shutdown and virsh start, when script want to detach device)

Additional
1.set enable_default_yum, if enable_default_yum = yes allow host and vm install kernel-rt from beaker-NFV repo
if enable_defult_yum=no, will use beaker --nvr to specify the host kernel, and use host kernel version to install  
kernel-rt in vm.

limitation
1.can't use to the newest kernel package to install.
 