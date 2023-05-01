#!/bin/bash
IMG_GUEST=http://netqe-infra01.knqe.lab.eng.bos.redhat.com/vm/rhel6.8.qcow2

echo "remove any VM if exist"
virsh list --all | sed -n 3~1p |
	awk '/[[:alpha:]]+/ {
		if ($3 == "running") {
			system("virsh shutdown "$2);
			sleep 2;
			system("virsh destroy "$2)
		};
		system("virsh undefine --managed-save --snapshots-metadata --remove-all-storage "$2)
	}'

echo "remove any vnet definition if exist"
virsh net-list --all | sed -n 3~1p |
	awk '/[[:alnum:]]+/ {
		system("virsh net-destroy "$1);
		sleep 2;
		system("virsh net-undefine "$1)
	}'

echo "Download guest image..."

echo "Create default network..."
virsh net-define /usr/share/libvirt/networks/default.xml
virsh net-start default
virsh net-autostart default

echo "create VFs..."
echo 16 > /sys/bus/pci/devices/0000:1b:00.0/sriov_numvfs

echo "create VMs..."
for ((i=0; i<16; i++))
do
	pushd "/var/lib/libvirt/images/" 1>/dev/null
	cp --remove-destination $(basename $IMG_GUEST) g$i.qcow2
	popd 1>/dev/null
	virt-install \
		--name g$i \
		--vcpus=2 \
		--ram=2048 \
		--disk path=/var/lib/libvirt/images/g$i.qcow2,device=disk,bus=virtio,format=qcow2 \
		--network bridge=virbr0,model=virtio \
		--boot hd \
		--accelerate \
		--force \
		--graphics vnc,listen=0.0.0.0 \
		--os-variant=rhel-unknown \
		--noautoconsole
	virsh list

	cat <<-EOF > g$i.xml
		<interface type='hostdev' managed='yes'>
			<source>
				<address type='pci' domain='0x0000' bus='0x1b' slot='0x$(printf "%02x" $((0x10+i/4)))' function='0x$(printf "%02x" $((i%4*2)))'/>
			</source>
			<mac address='00:de:ad:01:02:$(printf "%02x" $i)'/>
		</interface>

	EOF

	cat g$i.xml
	virsh attach-device g$i g$i.xml
done
